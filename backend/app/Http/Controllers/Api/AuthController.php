<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Models\User;
use App\Services\OtpService;
use App\Support\Phone;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    public function __construct(private OtpService $otp) {}

    public function requestCode(Request $request): JsonResponse
    {
        $this->otp->send($this->phone($request));

        return response()->json(['message' => 'Code envoyé.'], 202);
    }

    public function verifyCode(Request $request): JsonResponse
    {
        $data = $request->validate([
            'code' => ['required', 'string', 'max:10'],
            'device_name' => ['required', 'string', 'max:100'],
        ]);
        $phone = $this->phone($request);

        if (! $this->otp->verify($phone, $data['code'])) {
            throw ValidationException::withMessages(['code' => 'Ce code est invalide ou expiré.']);
        }

        $user = User::firstOrCreate(['phone' => $phone]);

        // L'équipe se connecte par e-mail sur l'administration, jamais par SMS.
        if (! $user->is_active || $user->isStaff()) {
            return response()->json(['message' => 'Ce compte ne peut pas se connecter à l\'application.'], 403);
        }

        $user->forceFill(['phone_verified_at' => now()])->save();

        return response()->json([
            'token' => $user->createToken($data['device_name'])->plainTextToken,
            'user' => new UserResource($user->load('city')),
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(status: 204);
    }

    private function phone(Request $request): string
    {
        $request->validate(['phone' => ['required', 'string', 'max:30']]);

        return Phone::normalize($request->input('phone'))
            ?? throw ValidationException::withMessages(['phone' => 'Ce numéro de téléphone est invalide.']);
    }
}
