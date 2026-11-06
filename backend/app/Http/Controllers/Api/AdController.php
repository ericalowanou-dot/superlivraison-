<?php

namespace App\Http\Controllers\Api;

use App\Enums\AdCategory;
use App\Enums\AdStatus;
use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Http\Resources\AdResource;
use App\Models\Ad;
use App\Services\AdModeration;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;
use Symfony\Component\HttpFoundation\StreamedResponse;

class AdController extends Controller
{
    /** Les publicités validées de la ville de l'utilisateur. */
    public function index(Request $request): AnonymousResourceCollection
    {
        $ads = Ad::approved()->where('city_id', $request->user()->city_id)->latest('approved_at')->latest('id');

        return AdResource::collection($ads->paginate(20));
    }

    /** Les envois de l'utilisateur, quel que soit leur statut. */
    public function mine(Request $request): AnonymousResourceCollection
    {
        return AdResource::collection(Ad::where('user_id', $request->user()->id)->latest('id')->paginate(20));
    }

    public function store(Request $request, AdModeration $moderation): JsonResponse
    {
        $user = $request->user();
        abort_unless($user->role === Role::Restaurant, 403);
        abort_if($user->city_id === null, 422, 'Choisissez votre ville avant de publier.');

        $data = $request->validate([
            'category' => ['required', Rule::enum(AdCategory::class)],
            'title' => ['required', 'string', 'min:3', 'max:120'],
            'description' => ['nullable', 'string', 'max:2000'],
            'image' => ['required', 'file', 'mimes:jpg,jpeg,png,webp', 'max:'.config('superlivraison.ad_image_max_kb')],
        ]);

        $ad = Ad::create([
            'user_id' => $user->id,
            'city_id' => $user->city_id,
            'category' => $data['category'],
            'title' => $data['title'],
            'description' => $data['description'] ?? null,
            'image_path' => $request->file('image')->store('ads/'.$user->id, config('superlivraison.media_disk')),
        ]);

        $moderation->submitted($ad);

        return (new AdResource($ad->refresh()))->response()->setStatusCode(201);
    }

    public function destroy(Request $request, Ad $ad): Response
    {
        abort_unless($ad->user_id === $request->user()->id, 404);
        $ad->delete();

        return response()->noContent();
    }

    public function image(Request $request, Ad $ad): StreamedResponse
    {
        $user = $request->user();
        abort_unless($ad->status === AdStatus::Approved || $ad->user_id === $user->id || $user->isStaff(), 404);

        return Storage::disk(config('superlivraison.media_disk'))->response($ad->image_path);
    }
}
