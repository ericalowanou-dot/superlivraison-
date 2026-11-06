<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\OrderResource;
use App\Http\Resources\ProductResource;
use App\Http\Resources\ShopResource;
use App\Models\Order;
use App\Models\Product;
use App\Models\Shop;
use App\Services\ShopCheckout;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\StreamedResponse;

class ShopController extends Controller
{
    /** Les boutiques ouvertes de la ville de l'utilisateur. */
    public function index(Request $request): AnonymousResourceCollection
    {
        $search = trim((string) $request->query('search'));

        $shops = Shop::open()
            ->where('city_id', $request->user()->city_id)
            ->when($search !== '', fn ($query) => $query->where(fn ($q) => $q
                ->where('name', 'like', "%{$search}%")
                ->orWhere('category', 'like', "%{$search}%")))
            ->orderBy('name');

        return ShopResource::collection($shops->paginate(20));
    }

    public function products(Shop $shop): AnonymousResourceCollection
    {
        abort_unless($shop->isOpen(), 404);

        return ProductResource::collection($shop->products()->where('is_active', true)->orderBy('name')->paginate(30));
    }

    public function checkout(Request $request, Shop $shop, ShopCheckout $checkout): JsonResponse
    {
        Gate::authorize('create', Order::class);

        $data = $request->validate([
            'client_uuid' => ['required', 'uuid'],
            'items' => ['required', 'array', 'min:1', 'max:50'],
            'items.*.product_id' => ['required', 'integer'],
            'items.*.quantity' => ['required', 'integer', 'min:1', 'max:99'],
            'delivery_lat' => ['required', 'numeric', 'between:-90,90'],
            'delivery_lng' => ['required', 'numeric', 'between:-180,180'],
            'delivery_landmark' => ['required', 'string', 'max:255'],
        ]);

        $order = $checkout->place($request->user(), $shop, $data);

        return (new OrderResource($order->refresh()->load(['items', 'shop'])))->response()->setStatusCode($order->wasRecentlyCreated ? 201 : 200);
    }

    public function image(Request $request, Shop $shop): StreamedResponse
    {
        abort_unless($shop->image_path !== null && $this->canSee($request, $shop), 404);

        return Storage::disk(config('superlivraison.media_disk'))->response($shop->image_path);
    }

    public function productImage(Request $request, Product $product): StreamedResponse
    {
        abort_unless($this->canSee($request, $product->shop), 404);

        return Storage::disk(config('superlivraison.media_disk'))->response($product->image_path);
    }

    private function canSee(Request $request, Shop $shop): bool
    {
        $user = $request->user();

        return $shop->isOpen() || $shop->owner_id === $user->id || $user->isStaff();
    }
}
