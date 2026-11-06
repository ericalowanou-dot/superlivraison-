<?php

namespace App\Http\Controllers\Api;

use App\Enums\OrderChannel;
use App\Enums\OrderStatus;
use App\Enums\PaymentMode;
use App\Exceptions\WorkflowException;
use App\Http\Controllers\Controller;
use App\Http\Resources\OrderResource;
use App\Models\Order;
use App\Services\OrderWorkflow;
use App\Support\Phone;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpFoundation\StreamedResponse;

class OrderController extends Controller
{
    public function __construct(private OrderWorkflow $workflow) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        $orders = $request->user()->orders()->latest('id')
            ->when($request->boolean('to_pay'), fn ($query) => $query
                ->where('status', OrderStatus::Confirmed)
                ->where('payment_mode', PaymentMode::MobileMoney)
                ->whereNull('paid_at'))
            ->when($request->query('kind') === 'courier', fn ($query) => $query->where('channel', OrderChannel::Courier))
            ->when($request->query('kind') === 'goods', fn ($query) => $query->where('channel', '!=', OrderChannel::Courier));

        return OrderResource::collection($orders->paginate(20));
    }

    public function store(Request $request): JsonResponse
    {
        Gate::authorize('create', Order::class);

        $data = $request->validate([
            'client_uuid' => ['required', 'uuid'],
            'request_text' => ['required', 'string', 'min:3', 'max:5000'],
            'voice_note_id' => ['nullable', 'integer', Rule::exists('voice_notes', 'id')->where('user_id', $request->user()->id)],
            'delivery_lat' => ['nullable', 'required_with:delivery_lng', 'numeric', 'between:-90,90'],
            'delivery_lng' => ['nullable', 'required_with:delivery_lat', 'numeric', 'between:-180,180'],
            'delivery_landmark' => ['required', 'string', 'max:255'],
        ]);

        $order = $this->workflow->create($request->user(), [
            ...$data,
            'channel' => empty($data['voice_note_id']) ? OrderChannel::Text : OrderChannel::Voice,
        ]);

        return (new OrderResource($order->refresh()))->response()->setStatusCode($order->wasRecentlyCreated ? 201 : 200);
    }

    /** Solliciter un livreur : le prix et l'affectation suivent le même circuit qu'une commande. */
    public function storeCourierRequest(Request $request): JsonResponse
    {
        Gate::authorize('create', Order::class);

        $data = $request->validate([
            'client_uuid' => ['required', 'uuid'],
            'recipient_phone' => ['required', 'string', 'max:30'],
            'delivery_lat' => ['required', 'numeric', 'between:-90,90'],
            'delivery_lng' => ['required', 'numeric', 'between:-180,180'],
            'delivery_landmark' => ['nullable', 'string', 'max:255'],
            'details' => ['nullable', 'string', 'max:1000'],
        ]);

        $phone = Phone::normalize($data['recipient_phone']);
        if ($phone === null) {
            throw ValidationException::withMessages(['recipient_phone' => 'Indiquez un numéro au format +22890000000.']);
        }

        $order = $this->workflow->create($request->user(), [
            'client_uuid' => $data['client_uuid'],
            'channel' => OrderChannel::Courier,
            'request_text' => $data['details'] ?? "Course vers {$phone}",
            'recipient_phone' => $phone,
            'delivery_lat' => $data['delivery_lat'],
            'delivery_lng' => $data['delivery_lng'],
            'delivery_landmark' => $data['delivery_landmark'] ?? 'Position indiquée sur la carte',
        ]);

        return (new OrderResource($order->refresh()))->response()->setStatusCode($order->wasRecentlyCreated ? 201 : 200);
    }

    public function show(Order $order): OrderResource
    {
        Gate::authorize('view', $order);

        return new OrderResource($order->load(['events', 'items', 'shop']));
    }

    public function acceptPrice(Request $request, Order $order): OrderResource
    {
        Gate::authorize('respond', $order);
        $data = $request->validate([
            'payment_mode' => ['required', Rule::enum(PaymentMode::class)],
            'price' => ['required', 'integer', 'min:1'],
        ]);

        return new OrderResource($this->workflow->acceptPrice($order, $request->user(), PaymentMode::from($data['payment_mode']), $data['price']));
    }

    public function refusePrice(Request $request, Order $order): OrderResource
    {
        Gate::authorize('respond', $order);
        $data = $request->validate(['reason' => ['nullable', 'string', 'max:255']]);

        return new OrderResource($this->workflow->refusePrice($order, $request->user(), $data['reason'] ?? null));
    }

    public function cancel(Request $request, Order $order): OrderResource
    {
        Gate::authorize('respond', $order);
        $data = $request->validate(['reason' => ['required', 'string', 'max:255']]);

        return new OrderResource($this->workflow->cancel($order, $request->user(), $data['reason']));
    }

    /** Recommander une commande précédente en un geste (C9). */
    public function reorder(Request $request, Order $order): JsonResponse
    {
        Gate::authorize('respond', $order);

        if ($order->channel === OrderChannel::Shop) {
            throw new WorkflowException('Repassez par la boutique pour recommander ces articles.');
        }

        $copy = $this->workflow->create($request->user(), [
            'client_uuid' => (string) Str::uuid(),
            'channel' => $order->channel === OrderChannel::Courier ? OrderChannel::Courier : OrderChannel::Text,
            'request_text' => $order->request_text,
            'recipient_phone' => $order->recipient_phone,
            'delivery_lat' => $order->delivery_lat,
            'delivery_lng' => $order->delivery_lng,
            'delivery_landmark' => $order->delivery_landmark,
        ]);

        return (new OrderResource($copy->refresh()))->response()->setStatusCode(201);
    }

    public function voice(Order $order): StreamedResponse
    {
        Gate::authorize('view', $order);
        abort_unless($order->voiceNote, 404);

        return Storage::disk(config('superlivraison.media_disk'))->response($order->voiceNote->path);
    }
}
