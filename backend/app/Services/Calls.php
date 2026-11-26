<?php

namespace App\Services;

use App\Contracts\PushSender;
use App\Enums\CallStatus;
use App\Exceptions\WorkflowException;
use App\Http\Resources\CallResource;
use App\Jobs\ExpireCall;
use App\Models\Call;
use App\Models\Order;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Throwable;

/**
 * Appels audio et vidéo entre le client et le livreur d'une course.
 *
 * Le serveur décide qui peut appeler, fait sonner l'autre téléphone (Firebase et temps réel)
 * et note l'appel dans la discussion. Le son et l'image passent par ZEGOCLOUD.
 */
class Calls
{
    public function __construct(private Chat $chat, private PushSender $push) {}

    public function start(User $caller, Order $order, bool $video): Call
    {
        if (! $this->chat->isParticipant($caller, $order)) {
            throw new WorkflowException('Les appels sont possibles quand un livreur est affecté à la course.');
        }
        if (! $this->chat->isOpen($order)) {
            throw new WorkflowException('La course est terminée : les appels ne sont plus possibles.');
        }
        if (! ZegoToken::fromConfig()->configured()) {
            throw new WorkflowException('Les appels ne sont pas encore disponibles.');
        }

        $callee = $this->chat->peerOf($caller, $order);

        $order->calls()->where('status', CallStatus::Ringing)->get()->each(fn (Call $stale) => $this->expireIfStale($stale));

        $call = DB::transaction(function () use ($caller, $callee, $order, $video) {
            // Un seul appel à la fois par course. Un appel oublié depuis longtemps ne bloque plus.
            $busy = $order->calls()
                ->whereIn('status', [CallStatus::Ringing, CallStatus::Ongoing])
                ->where('created_at', '>', now()->subHours(4))
                ->lockForUpdate()
                ->exists();
            if ($busy) {
                throw new WorkflowException('Un appel est déjà en cours pour cette course.');
            }

            return $order->calls()->create([
                'caller_id' => $caller->id,
                'callee_id' => $callee->id,
                'video' => $video,
                'status' => CallStatus::Ringing,
            ]);
        });

        $this->chat->broadcastCall($call, 'call.ringing', ['call' => $this->resource($call)]);
        $this->notifyCallee($call, 'call', [
            'caller_name' => $this->displayName($caller, $order),
            'reference' => (string) $order->reference,
            'video' => $video ? '1' : '0',
        ]);

        // Une file « sync » n'attend pas : le délai est alors vérifié à la prochaine lecture de l'appel.
        if (config('queue.default') !== 'sync') {
            ExpireCall::dispatch($call->id)->delay(now()->addSeconds($this->ringSeconds()));
        }

        return $call;
    }

    public function accept(User $user, Call $call): Call
    {
        if ($user->id !== $call->callee_id) {
            throw new WorkflowException('Seule la personne appelée peut décrocher.');
        }
        $this->expireIfStale($call);

        $accepted = Call::whereKey($call->id)->where('status', CallStatus::Ringing)
            ->update(['status' => CallStatus::Ongoing, 'answered_at' => now(), 'updated_at' => now()]);
        $call->refresh();

        if ($accepted === 0) {
            throw new WorkflowException('Cet appel est terminé.');
        }

        $this->chat->broadcastCall($call, 'call.accepted', ['call' => $this->resource($call)]);

        return $call;
    }

    /** Refuser, annuler ou raccrocher : le résultat dépend de qui le fait et du moment. */
    public function hangUp(User $user, Call $call): Call
    {
        $status = match (true) {
            $call->status === CallStatus::Ongoing => CallStatus::Ended,
            $user->id === $call->callee_id => CallStatus::Declined,
            default => CallStatus::Missed,
        };

        return $this->finish($call, $status);
    }

    /** Un appel qui sonne depuis trop longtemps passe en manqué. */
    public function expireIfStale(Call $call): Call
    {
        if ($call->status === CallStatus::Ringing && $call->created_at->lte(now()->subSeconds($this->ringSeconds()))) {
            return $this->expire($call);
        }

        return $call;
    }

    private function ringSeconds(): int
    {
        return (int) config('superlivraison.call_ring_seconds');
    }

    public function expire(Call $call): Call
    {
        return $call->status === CallStatus::Ringing ? $this->finish($call, CallStatus::Missed) : $call;
    }

    /**
     * Ce qu'il faut au téléphone pour rejoindre l'appel. Le jeton remplace l'AppSign :
     * aucune clé secrète n'est mise dans l'appli.
     *
     * @return array{app_id: int, token: string, room_id: string, user_id: string, stream_id: string, peer_stream_id: string}
     */
    public function credentials(User $user, Call $call): array
    {
        $zego = ZegoToken::fromConfig();
        $peerId = $user->id === $call->caller_id ? $call->callee_id : $call->caller_id;

        return [
            'app_id' => $zego->appId(),
            'token' => $zego->generate(Call::zegoUserId($user->id), (int) config('superlivraison.zego.token_ttl_seconds')),
            'room_id' => $call->roomId(),
            'user_id' => Call::zegoUserId($user->id),
            'stream_id' => $call->streamId($user->id),
            'peer_stream_id' => $call->streamId($peerId),
        ];
    }

    private function finish(Call $call, CallStatus $status): Call
    {
        // Les deux téléphones peuvent raccrocher en même temps : un seul l'emporte.
        $finished = Call::whereKey($call->id)
            ->whereIn('status', [CallStatus::Ringing, CallStatus::Ongoing])
            ->update(['status' => $status, 'ended_at' => now(), 'updated_at' => now()]);
        $call->refresh();

        if ($finished === 0) {
            return $call;
        }

        $this->chat->broadcastCall($call, 'call.ended', ['call' => $this->resource($call)]);
        // Arrête la sonnerie si l'autre téléphone sonne encore.
        $this->notifyCallee($call, 'call_ended');
        $this->chat->recordCall($call);

        if ($status === CallStatus::Missed) {
            $this->notifyMissed($call);
        }

        return $call;
    }

    /** @param array<string, string> $extra */
    private function notifyCallee(Call $call, string $kind, array $extra = []): void
    {
        $data = [
            'kind' => $kind,
            'call_id' => (string) $call->id,
            'order_id' => (string) $call->order_id,
            ...$extra,
        ];

        foreach ($call->callee->deviceTokens()->pluck('token') as $token) {
            try {
                $this->push->sendData($token, $data, $this->ringSeconds());
            } catch (Throwable $e) {
                // Le téléphone ne sonnera pas, mais l'appel reste visible dans la discussion ouverte.
                report($e);
            }
        }
    }

    private function notifyMissed(Call $call): void
    {
        $order = $call->order;
        $title = $this->displayName($call->caller, $order);
        $body = $call->video ? 'Appel vidéo manqué' : 'Appel vocal manqué';

        foreach ($call->callee->deviceTokens()->pluck('token') as $token) {
            try {
                $this->push->send($token, $title, $body, [
                    'kind' => 'message',
                    'order_id' => (string) $order->id,
                    'reference' => (string) $order->reference,
                ]);
            } catch (Throwable $e) {
                report($e);
            }
        }
    }

    private function displayName(User $user, Order $order): string
    {
        return $user->business_name ?? $user->name ?? ($user->id === $order->courier_id ? 'Votre livreur' : 'Votre client');
    }

    /** @return array<string, mixed> */
    private function resource(Call $call): array
    {
        return (new CallResource($call))->resolve();
    }
}
