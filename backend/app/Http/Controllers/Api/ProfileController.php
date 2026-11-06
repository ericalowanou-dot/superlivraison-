<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Models\DeviceToken;
use App\Services\AccountService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class ProfileController extends Controller
{
    public function show(Request $request): UserResource
    {
        return new UserResource($request->user()->load('city'));
    }

    public function update(Request $request): UserResource
    {
        $data = $request->validate([
            'name' => ['sometimes', 'nullable', 'string', 'max:120'],
            'business_name' => ['sometimes', 'nullable', 'string', 'max:120'],
            'language_code' => ['sometimes', 'string', Rule::exists('languages', 'code')->where('is_active', true)],
            'city_id' => ['sometimes', 'integer', Rule::exists('cities', 'id')->where('is_active', true)],
        ]);

        $request->user()->update($data);

        return new UserResource($request->user()->load('city'));
    }

    public function destroy(Request $request, AccountService $accounts): JsonResponse
    {
        $accounts->delete($request->user());

        return response()->json(status: 204);
    }

    public function registerDevice(Request $request): JsonResponse
    {
        $data = $request->validate([
            'token' => ['required', 'string', 'max:512'],
            'platform' => ['required', Rule::in(['android', 'ios'])],
        ]);

        // Un téléphone peut changer de compte : le jeton suit le dernier connecté.
        DeviceToken::updateOrCreate(
            ['token' => $data['token']],
            ['user_id' => $request->user()->id, 'platform' => $data['platform']],
        );

        return response()->json(status: 204);
    }

    public function notifications(Request $request): JsonResponse
    {
        return response()->json(
            $request->user()->notifications()->latest()->paginate(30)->through(fn ($n) => [
                'id' => $n->id,
                'title' => $n->data['title'] ?? null,
                'body' => $n->data['body'] ?? null,
                'order_id' => $n->data['order_id'] ?? null,
                'read' => $n->read_at !== null,
                'created_at' => $n->created_at,
            ])
        );
    }

    public function markNotificationsRead(Request $request): JsonResponse
    {
        $request->user()->unreadNotifications->markAsRead();

        return response()->json(status: 204);
    }
}
