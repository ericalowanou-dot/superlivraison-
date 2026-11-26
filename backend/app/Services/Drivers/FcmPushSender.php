<?php

namespace App\Services\Drivers;

use App\Contracts\PushSender;
use App\Models\DeviceToken;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;

/**
 * Notifications Android et iOS par Firebase Cloud Messaging (API HTTP v1).
 *
 * Le serveur s'authentifie avec la clé d'un compte de service Firebase :
 * il signe un jeton JWT et l'échange contre un jeton d'accès Google, gardé en cache une heure.
 */
class FcmPushSender implements PushSender
{
    private const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

    /** @var array{project_id: string, client_email: string, private_key: string, token_uri?: string} */
    private array $account;

    public function __construct(string $credentialsPath)
    {
        $json = is_file($credentialsPath) ? file_get_contents($credentialsPath) : false;
        $account = $json === false ? null : json_decode($json, true);

        if (! is_array($account) || empty($account['project_id']) || empty($account['client_email']) || empty($account['private_key'])) {
            throw new RuntimeException('Clé Firebase introuvable ou invalide : renseignez FIREBASE_CREDENTIALS.');
        }

        $this->account = $account;
    }

    public function send(string $token, string $title, string $body, array $data = []): void
    {
        $response = Http::withToken($this->accessToken())
            ->timeout(10)
            ->post("https://fcm.googleapis.com/v1/projects/{$this->account['project_id']}/messages:send", [
                'message' => [
                    'token' => $token,
                    'notification' => ['title' => $title, 'body' => $body],
                    // Les valeurs doivent être des chaînes pour Firebase.
                    'data' => array_map('strval', $data),
                    'android' => [
                        'priority' => 'high',
                        'notification' => ['sound' => 'default'],
                    ],
                    'apns' => [
                        'headers' => ['apns-priority' => '10'],
                        'payload' => ['aps' => ['sound' => 'default']],
                    ],
                ],
            ]);

        if ($response->successful()) {
            return;
        }

        // Application désinstallée ou jeton périmé : on l'oublie pour ne plus réessayer.
        $code = $response->json('error.details.0.errorCode') ?? $response->json('error.status');
        if (in_array($code, ['UNREGISTERED', 'NOT_FOUND'], true)) {
            DeviceToken::where('token', $token)->delete();
            Log::info('Jeton de notification supprimé', ['code' => $code]);

            return;
        }

        // Une demande refusée telle quelle le restera : inutile de réessayer.
        if ($code === 'INVALID_ARGUMENT') {
            Log::warning('Notification refusée par Firebase', ['error' => $response->json('error.message')]);

            return;
        }

        if ($response->status() === 401) {
            Cache::forget($this->cacheKey());
        }

        // Les autres erreurs, par exemple un quota dépassé, font réessayer la tâche.
        $response->throw();
    }

    private function accessToken(): string
    {
        return Cache::remember($this->cacheKey(), now()->addMinutes(50), function (): string {
            $now = time();
            $tokenUri = $this->account['token_uri'] ?? 'https://oauth2.googleapis.com/token';

            $assertion = $this->jwt([
                'iss' => $this->account['client_email'],
                'scope' => self::SCOPE,
                'aud' => $tokenUri,
                'iat' => $now,
                'exp' => $now + 3600,
            ]);

            return Http::asForm()->timeout(10)->post($tokenUri, [
                'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                'assertion' => $assertion,
            ])->throw()->json('access_token');
        });
    }

    /** @param array<string, mixed> $claims */
    private function jwt(array $claims): string
    {
        $encode = fn (array $part) => rtrim(strtr(base64_encode(json_encode($part)), '+/', '-_'), '=');
        $unsigned = $encode(['alg' => 'RS256', 'typ' => 'JWT']).'.'.$encode($claims);

        if (! openssl_sign($unsigned, $signature, $this->account['private_key'], OPENSSL_ALGO_SHA256)) {
            throw new RuntimeException('Signature Firebase impossible : la clé privée est invalide.');
        }

        return $unsigned.'.'.rtrim(strtr(base64_encode($signature), '+/', '-_'), '=');
    }

    private function cacheKey(): string
    {
        return 'fcm-access-token:'.md5($this->account['client_email']);
    }
}
