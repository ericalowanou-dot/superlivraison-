<?php

namespace App\Http\Controllers\Api;

use App\Enums\MessageType;
use App\Http\Controllers\Controller;
use App\Http\Resources\MessageResource;
use App\Models\Message;
use App\Models\Order;
use App\Services\Chat;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;
use Symfony\Component\HttpFoundation\StreamedResponse;

class MessageController extends Controller
{
    public function __construct(private Chat $chat) {}

    /** L'historique, ou seulement les messages après [after_id] pour rattraper une coupure. */
    public function index(Request $request, Order $order): JsonResponse
    {
        Gate::authorize('view', $order);
        $data = $request->validate(['after_id' => ['nullable', 'integer', 'min:0']]);
        $user = $request->user();

        $messages = $order->messages()
            ->with('call')
            ->when(isset($data['after_id']), fn ($query) => $query->where('id', '>', $data['after_id']))
            ->latest('id')
            ->limit(200)
            ->get()
            ->reverse()
            ->values();

        // Le téléphone a récupéré ces messages : l'expéditeur voit les deux coches.
        $this->chat->acknowledge($user, $order, read: false);

        $peer = $this->chat->peerOf($user, $order);

        return response()->json([
            'data' => MessageResource::collection($messages)->resolve(),
            'meta' => [
                'me' => $user->id,
                'can_send' => $this->chat->isParticipant($user, $order) && $this->chat->isOpen($order),
                'has_courier' => $order->courier_id !== null,
                'peer' => $peer ? [
                    'id' => $peer->id,
                    'name' => $peer->business_name ?? $peer->name ?? ($peer->id === $order->courier_id ? 'Votre livreur' : 'Votre client'),
                    'phone' => $peer->phone,
                    'is_courier' => $peer->id === $order->courier_id,
                ] : null,
            ],
        ]);
    }

    public function store(Request $request, Order $order): JsonResponse
    {
        Gate::authorize('view', $order);

        $data = $request->validate([
            'client_uuid' => ['required', 'uuid'],
            'type' => ['required', Rule::enum(MessageType::class)],
            'body' => ['nullable', 'required_if:type,text', 'string', 'max:4000'],
            'audio' => ['required_if:type,voice', 'prohibited_unless:type,voice', 'file', 'extensions:m4a,aac,mp3,ogg,opus,wav', 'mimetypes:audio/mp4,audio/x-m4a,audio/aac,audio/mpeg,audio/ogg,audio/opus,audio/wav,audio/x-wav,video/mp4', 'max:'.config('superlivraison.voice_max_kb')],
            'duration_seconds' => ['nullable', 'integer', 'min:1', 'max:600'],
            'image' => ['required_if:type,image', 'prohibited_unless:type,image', 'image', 'max:'.config('superlivraison.ad_image_max_kb')],
            'lat' => ['required_if:type,location', 'nullable', 'numeric', 'between:-90,90'],
            'lng' => ['required_if:type,location', 'nullable', 'numeric', 'between:-180,180'],
        ]);

        $type = MessageType::from($data['type']);
        $file = match ($type) {
            MessageType::Voice => $request->file('audio'),
            MessageType::Image => $request->file('image'),
            default => null,
        };

        $message = $this->chat->send($request->user(), $order, [
            ...$data,
            'body' => in_array($type, [MessageType::Text, MessageType::Image], true) ? ($data['body'] ?? null) : null,
            'duration_seconds' => $type === MessageType::Voice ? ($data['duration_seconds'] ?? null) : null,
            'lat' => $type === MessageType::Location ? $data['lat'] : null,
            'lng' => $type === MessageType::Location ? $data['lng'] : null,
        ], $file);

        return (new MessageResource($message))->response()->setStatusCode($message->wasRecentlyCreated ? 201 : 200);
    }

    /** Accusé de réception ou de lecture, jusqu'au message [up_to_id]. */
    public function receipt(Request $request, Order $order): Response
    {
        Gate::authorize('view', $order);
        $data = $request->validate([
            'up_to_id' => ['nullable', 'integer', 'min:1'],
            'read' => ['required', 'boolean'],
        ]);

        $this->chat->acknowledge($request->user(), $order, (bool) $data['read'], $data['up_to_id'] ?? null);

        return response()->noContent();
    }

    public function typing(Request $request, Order $order): Response
    {
        Gate::authorize('view', $order);
        $this->chat->typing($request->user(), $order);

        return response()->noContent();
    }

    public function media(Message $message): StreamedResponse
    {
        Gate::authorize('view', $message->order);
        abort_unless($message->path, 404);

        return Storage::disk(config('superlivraison.media_disk'))->response($message->path);
    }
}
