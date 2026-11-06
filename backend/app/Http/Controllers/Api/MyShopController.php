<?php

namespace App\Http\Controllers\Api;

use App\Enums\PayoutStatus;
use App\Enums\ReviewStatus;
use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Http\Resources\PayoutResource;
use App\Http\Resources\ProductResource;
use App\Http\Resources\SellerOrderResource;
use App\Http\Resources\ShopResource;
use App\Models\Product;
use App\Models\Shop;
use App\Services\ShopModeration;
use App\Support\Phone;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

/** Espace vendeur : un compte tient une seule boutique. */
class MyShopController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        $shop = $this->find($request);

        return response()->json(['shop' => $shop ? new ShopResource($shop) : null]);
    }

    /** Crée la boutique, ou la modifie. Une boutique refusée repart en validation. */
    public function save(Request $request, ShopModeration $moderation): JsonResponse
    {
        $user = $request->user();
        abort_unless($user->role === Role::Restaurant, 403);
        abort_if($user->city_id === null, 422, 'Choisissez votre ville avant de créer une boutique.');

        $data = $request->validate([
            'name' => ['required', 'string', 'min:2', 'max:120'],
            'category' => ['nullable', 'string', 'max:100'],
            'description' => ['nullable', 'string', 'max:2000'],
            'phone' => ['required', 'string', 'max:30'],
            'landmark' => ['required', 'string', 'max:255'],
            'lat' => ['nullable', 'required_with:lng', 'numeric', 'between:-90,90'],
            'lng' => ['nullable', 'required_with:lat', 'numeric', 'between:-180,180'],
            'image' => ['nullable', 'file', 'mimes:jpg,jpeg,png,webp', 'max:'.config('superlivraison.ad_image_max_kb')],
        ]);

        $data['phone'] = Phone::normalize($data['phone']);
        if ($data['phone'] === null) {
            throw ValidationException::withMessages(['phone' => 'Indiquez un numéro au format +22890000000.']);
        }

        $shop = $this->find($request) ?? new Shop(['owner_id' => $user->id, 'city_id' => $user->city_id]);
        $resubmitted = $shop->status === ReviewStatus::Rejected;
        $isNew = ! $shop->exists;
        unset($data['image']);
        $shop->fill($data);

        if ($request->hasFile('image')) {
            $previous = $shop->image_path;
            $shop->image_path = $request->file('image')->store('shops/'.$user->id, config('superlivraison.media_disk'));
            if ($previous !== null) {
                Storage::disk(config('superlivraison.media_disk'))->delete($previous);
            }
        }

        if ($resubmitted) {
            $shop->forceFill(['status' => ReviewStatus::Pending, 'rejection_reason' => null]);
        }

        $shop->save();

        if ($isNew || $resubmitted) {
            $moderation->submitted($shop);
        }

        return (new ShopResource($shop->refresh()))->response()->setStatusCode($isNew ? 201 : 200);
    }

    public function products(Request $request): AnonymousResourceCollection
    {
        return ProductResource::collection($this->owned($request)->products()->orderBy('name')->paginate(50));
    }

    public function storeProduct(Request $request): JsonResponse
    {
        $shop = $this->owned($request);
        $data = $this->validateProduct($request, imageRequired: true);
        unset($data['image']);

        $product = $shop->products()->create([
            ...$data,
            'image_path' => $request->file('image')->store('products/'.$shop->id, config('superlivraison.media_disk')),
        ]);

        return (new ProductResource($product->refresh()))->response()->setStatusCode(201);
    }

    public function updateProduct(Request $request, Product $product): ProductResource
    {
        abort_unless($product->shop_id === $this->owned($request)->id, 404);

        $data = $this->validateProduct($request, imageRequired: false);
        unset($data['image']);
        $product->fill($data);

        if ($request->hasFile('image')) {
            $previous = $product->image_path;
            $product->image_path = $request->file('image')->store('products/'.$product->shop_id, config('superlivraison.media_disk'));
            Storage::disk(config('superlivraison.media_disk'))->delete($previous);
        }

        $product->save();

        return new ProductResource($product);
    }

    public function destroyProduct(Request $request, Product $product): Response
    {
        abort_unless($product->shop_id === $this->owned($request)->id, 404);
        $product->delete();

        return response()->noContent();
    }

    public function orders(Request $request): AnonymousResourceCollection
    {
        return SellerOrderResource::collection(
            $this->owned($request)->orders()->with('items')->latest('id')->paginate(20)
        );
    }

    public function payouts(Request $request): JsonResponse
    {
        $shop = $this->owned($request);

        return PayoutResource::collection($shop->payouts()->with('order')->latest('id')->paginate(20))
            ->additional(['to_receive' => (int) $shop->payouts()->where('status', PayoutStatus::Pending)->sum('amount')])
            ->response();
    }

    /** @return array<string, mixed> */
    private function validateProduct(Request $request, bool $imageRequired): array
    {
        return $request->validate([
            'name' => ['required', 'string', 'min:2', 'max:120'],
            'description' => ['nullable', 'string', 'max:2000'],
            'price' => ['required', 'integer', 'min:1', 'max:100000000'],
            'stock' => ['nullable', 'integer', 'min:0', 'max:1000000'],
            'is_active' => ['sometimes', 'boolean'],
            'image' => [$imageRequired ? 'required' : 'nullable', 'file', 'mimes:jpg,jpeg,png,webp', 'max:'.config('superlivraison.ad_image_max_kb')],
        ]);
    }

    private function find(Request $request): ?Shop
    {
        return Shop::where('owner_id', $request->user()->id)->first();
    }

    private function owned(Request $request): Shop
    {
        return $this->find($request) ?? abort(404, 'Créez d\'abord votre boutique.');
    }
}
