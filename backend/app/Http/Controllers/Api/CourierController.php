<?php

namespace App\Http\Controllers\Api;

use App\Enums\OrderStatus;
use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Http\Resources\OrderResource;
use App\Models\Order;
use App\Services\OrderWorkflow;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Gate;

class CourierController extends Controller
{
    public function __construct(private OrderWorkflow $workflow) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        abort_unless($request->user()->role === Role::Courier, 403);

        return OrderResource::collection(
            $request->user()->deliveries()
                ->with(['items', 'shop'])
                ->whereIn('status', [OrderStatus::Confirmed, OrderStatus::Preparing, OrderStatus::Delivering])
                ->latest('id')
                ->get()
        );
    }

    public function start(Request $request, Order $order): OrderResource
    {
        Gate::authorize('deliver', $order);

        return new OrderResource($this->workflow->startDelivery($order, $request->user()));
    }

    public function delivered(Request $request, Order $order): OrderResource
    {
        Gate::authorize('deliver', $order);

        return new OrderResource($this->workflow->markDelivered($order, $request->user()));
    }
}
