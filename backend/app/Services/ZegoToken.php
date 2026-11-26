<?php

namespace App\Services;

use RuntimeException;

/**
 * Jeton d'accès ZEGOCLOUD (version « 04 »), signé avec le ServerSecret qui ne quitte jamais le serveur.
 * Reprend l'algorithme de référence de ZEGOCLOUD (zego_server_assistant, version PHP).
 */
class ZegoToken
{
    public function __construct(private int $appId, private string $secret) {}

    public static function fromConfig(): self
    {
        return new self((int) config('superlivraison.zego.app_id'), (string) config('superlivraison.zego.server_secret'));
    }

    public function configured(): bool
    {
        return $this->appId > 0 && strlen($this->secret) === 32;
    }

    public function appId(): int
    {
        return $this->appId;
    }

    public function generate(string $userId, int $ttlSeconds): string
    {
        if (! $this->configured()) {
            throw new RuntimeException('ZEGOCLOUD n\'est pas configuré : renseignez ZEGO_APP_ID et ZEGO_SERVER_SECRET.');
        }

        $now = time();
        $expire = $now + $ttlSeconds;
        $plain = json_encode([
            'app_id' => $this->appId,
            'user_id' => $userId,
            'nonce' => random_int(0, 2147483647),
            'ctime' => $now,
            'expire' => $expire,
            'payload' => '',
        ], JSON_BIGINT_AS_STRING);

        // Vecteur d'initialisation de 16 caractères alphanumériques, comme l'implémentation de référence.
        $alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
        $iv = '';
        for ($i = 0; $i < 16; $i++) {
            $iv .= $alphabet[random_int(0, 35)];
        }

        $encrypted = openssl_encrypt($plain, 'aes-256-cbc', $this->secret, OPENSSL_RAW_DATA, $iv);
        if ($encrypted === false) {
            throw new RuntimeException('Chiffrement du jeton ZEGOCLOUD impossible.');
        }

        $binary = pack('J', $expire).pack('n', strlen($iv)).$iv.pack('n', strlen($encrypted)).$encrypted;

        return '04'.base64_encode($binary);
    }
}
