<?php

namespace App\Services;

use App\Enums\MessageType;
use App\Enums\OrderStatus;
use App\Events\ChatEvent;
use App\Exceptions\WorkflowException;
use App\Http\Resources\MessageResource;
use App\Jobs\SendMessagePush;
use App\Models\Call;
use App\Models\Message;
use App\Models\Order;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Throwable;

/**
 * La discussion entre le client et le livreur d'une course.
 * Elle s'ouvre dès qu'un livreur est affecté et passe en lecture seule une fois la course terminée.
 */
class Chat
{
    public function isParticipant(User $user, Order $order): bool
    {
        return $order->courier_id !== null
            && in_array($user->id, [$order->restaurant_id, $order->courier_id], true);
    }

    public function isOpen(Order $order): bool
    {
        return $order->courier_id !== null
            && ! in_array($order->status, [OrderStatus::Delivered, OrderStatus::Cancelled], true);
    }

    public function peerOf(User $user, Order $order): ?User
    {
        return match ($user->id) {
            $order->restaurant_id => $order->courier,
            $order->courier_id => $order->restaurant,
            default => null,
        };
    }

    /** @param array<string, mixed> $data */
    public function send(User $sender, Order $order, array $data, ?UploadedFile $file = null): Message
    {
        if (! $this->isParticipant($sender, $order)) {
            throw new WorkflowException('La discussion s\'ouvre quand un livreur est affecté à la course.');
        }

        // Un renvoi après une coupure réseau retrouve le message déjà reçu.
        $existing = Message::where('sender_id', $sender->id)->where('client_uuid', $data['client_uuid'])->first();
        if ($existing) {
            return $existing;
        }

        if (! $this->isOpen($order)) {
            throw new WorkflowException('La course est terminée : la discussion est fermée.');
        }

        $path = $file?->store('chat/'.$order->id, config('superlivraison.media_disk'));

        $message = DB::transaction(fn () => $order->messages()->create([
            'client_uuid' => $data['client_uuid'],
            'sender_id' => $sender->id,
            'type' => $data['type'],
            'body' => $data['body'] ?? null,
            'path' => $path ?: null,
            'duration_seconds' => $data['duration_seconds'] ?? null,
            'lat' => $data['lat'] ?? null,
            'lng' => $data['lng'] ?? null,
        ]));

        $this->broadcast($order, 'message.sent', ['message' => (new MessageResource($message))->resolve()]);

        if ($peer = $this->peerOf($sender, $order)) {
            // Laisse quelques secondes au destinataire connecté pour lire avant de notifier son téléphone.
            SendMessagePush::dispatch($message, $peer)->delay(now()->addSeconds(5));
        }

        return $message;
    }

    /** Note un appel terminé dans l'historique de la discussion. */
    public function recordCall(Call $call): Message
    {
        $message = $call->order->messages()->create([
            'client_uuid' => (string) Str::uuid(),
            'sender_id' => $call->caller_id,
            'call_id' => $call->id,
            'type' => MessageType::Call,
        ]);

        $this->broadcast($call->order, 'message.sent', ['message' => (new MessageResource($message->load('call')))->resolve()]);

        return $message;
    }

    /** @param array<string, mixed> $payload */
    public function broadcastCall(Call $call, string $name, array $payload): void
    {
        $this->broadcast($call->order, $name, $payload);
    }

    /**
     * Marque comme reçus, ou lus, les messages de l'autre personne jusqu'à [$upToId].
     * Sans [$upToId], tous les messages déjà présents sont concernés.
     */
    public function acknowledge(User $reader, Order $order, bool $read, ?int $upToId = null): void
    {
        if (! $this->isParticipant($reader, $order)) {
            return;
        }

        $now = now();
        $incoming = fn () => $order->messages()
            ->where('sender_id', '!=', $reader->id)
            ->when($upToId !== null, fn ($query) => $query->where('id', '<=', $upToId));

        $last = $incoming()->max('id');
        if ($last === null) {
            return;
        }

        $delivered = $incoming()->whereNull('delivered_at')->update(['delivered_at' => $now]);
        $newlyRead = $read ? $incoming()->whereNull('read_at')->update(['read_at' => $now]) : 0;

        if ($delivered > 0 || $newlyRead > 0) {
            $this->broadcast($order, 'message.receipt', [
                'reader_id' => $reader->id,
                'up_to_id' => $last,
                'delivered_at' => $now->toJSON(),
                'read_at' => $read ? $now->toJSON() : null,
            ]);
        }
    }

    public function typing(User $user, Order $order): void
    {
        if ($this->isParticipant($user, $order) && $this->isOpen($order)) {
            $this->broadcast($order, 'user.typing', ['user_id' => $user->id]);
        }
    }

    /**
     * Une panne du serveur temps réel ne doit pas faire échouer l'envoi :
     * le message est enregistré et le téléphone le récupère à la prochaine lecture.
     *
     * @param  array<string, mixed>  $payload
     */
    private function broadcast(Order $order, string $name, array $payload): void
    {
        try {
            broadcast(new ChatEvent($order->id, $name, $payload));
        } catch (Throwable $e) {
            report($e);
        }
    }
}
