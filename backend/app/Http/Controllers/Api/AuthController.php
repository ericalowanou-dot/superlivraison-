<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Models\User;
use App\Services\OtpService;
use App\Support\Phone;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Password;
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

    public function register(Request $request): JsonResponse
    {
        $request->merge(['email' => mb_strtolower(trim((string) $request->input('email')))]);
        $data = $request->validate([
            'name' => ['required', 'string', 'max:120'],
            'email' => ['required', 'string', 'email', 'max:255', Rule::unique('users', 'email')],
            'phone' => ['nullable', 'string', 'max:30'],
            'password' => ['required', 'string', 'confirmed', Password::min(8)],
            'device_name' => ['required', 'string', 'max:100'],
        ], [
            'email.unique' => 'Un compte existe déjà avec cette adresse e-mail.',
        ]);

        // Le numéro est facultatif ; il sert au livreur pour appeler et au paiement mobile.
        $phone = null;
        if (filled($data['phone'] ?? null)) {
            $phone = Phone::normalize($data['phone'])
                ?? throw ValidationException::withMessages(['phone' => 'Ce numéro de téléphone est invalide.']);
            if (User::where('phone', $phone)->exists()) {
                throw ValidationException::withMessages(['phone' => 'Ce numéro est déjà utilisé par un autre compte.']);
            }
        }

        $user = User::create([
            'name' => $data['name'],
            'email' => $data['email'],
            'phone' => $phone,
            'password' => $data['password'],
        ]);

        return response()->json($this->signedIn($user, $data['device_name']), 201);
    }

    public function login(Request $request): JsonResponse
    {
        $data = $request->validate([
            'email' => ['required', 'string', 'max:255'],
            'password' => ['required', 'string', 'max:255'],
            'device_name' => ['required', 'string', 'max:100'],
        ]);

        $user = User::where('email', mb_strtolower(trim($data['email'])))->first();
        if ($user === null || $user->password === null || ! Hash::check($data['password'], $user->password)) {
            throw ValidationException::withMessages(['email' => 'E-mail ou mot de passe incorrect.']);
        }

        // L'équipe se connecte sur l'administration, pas dans l'application.
        if (! $user->is_active || $user->isStaff()) {
            return response()->json(['message' => 'Ce compte ne peut pas se connecter à l\'application.'], 403);
        }

        return response()->json($this->signedIn($user, $data['device_name']));
    }

    private function signedIn(User $user, string $device): array
    {
        return [
            'token' => $user->createToken($device)->plainTextToken,
            'user' => new UserResource($user->load('city')),
        ];
    }

    public function logout(Request $request): JsonResponse
    {
        // Le téléphone ne doit plus recevoir les notifications du compte qu'il quitte.
        $device = $request->validate(['device_token' => ['nullable', 'string', 'max:512']])['device_token'] ?? null;
        if ($device !== null) {
            $request->user()->deviceTokens()->where('token', $device)->delete();
        }

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
