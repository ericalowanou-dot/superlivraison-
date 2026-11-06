<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\ShopResource;
use App\Models\Shop;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\StreamedResponse;

class ShopController extends Controller
{
    /** Les boutiques actives de la ville de l'utilisateur. */
    public function index(Request $request): AnonymousResourceCollection
    {
        $search = trim((string) $request->query('search'));

        $shops = Shop::active()
            ->where('city_id', $request->user()->city_id)
            ->when($search !== '', fn ($query) => $query->where(fn ($q) => $q
                ->where('name', 'like', "%{$search}%")
                ->orWhere('category', 'like', "%{$search}%")))
            ->orderBy('name');

        return ShopResource::collection($shops->paginate(20));
    }

    public function image(Shop $shop): StreamedResponse
    {
        abort_unless($shop->is_active && $shop->image_path !== null, 404);

        return Storage::disk(config('superlivraison.media_disk'))->response($shop->image_path);
    }
}
