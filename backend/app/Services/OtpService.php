<?php

namespace App\Services;

use App\Contracts\SmsSender;
use App\Models\OtpCode;
use App\Models\User;

class OtpService
{
    public function __construct(private SmsSender $sms) {}

    public function send(string $phone): void
    {
        // Même réponse pour tous : on ne révèle pas si un compte est bloqué.
        if (User::where('phone', $phone)->where('is_active', false)->exists()) {
            return;
        }

        $length = (int) config('superlivraison.otp.length');
        $code = str_pad((string) random_int(0, 10 ** $length - 1), $length, '0', STR_PAD_LEFT);

        OtpCode::where('phone', $phone)->whereNull('consumed_at')->update(['consumed_at' => now()]);
        OtpCode::create([
            'phone' => $phone,
            'code_hash' => $this->hash($phone, $code),
            'expires_at' => now()->addMinutes((int) config('superlivraison.otp.ttl_minutes')),
        ]);

        $this->sms->send($phone, "Votre code de connexion est {$code}. Ne le partagez avec personne.");
    }

    public function verify(string $phone, string $code): bool
    {
        $otp = OtpCode::where('phone', $phone)
            ->whereNull('consumed_at')
            ->where('expires_at', '>', now())
            ->latest('id')
            ->first();

        if (! $otp || $otp->attempts >= (int) config('superlivraison.otp.max_attempts')) {
            return false;
        }

        if (! hash_equals($otp->code_hash, $this->hash($phone, $code))) {
            $otp->increment('attempts');

            return false;
        }

        // Le code ne sert qu'une fois, même si deux requêtes arrivent ensemble.
        return OtpCode::whereKey($otp->id)->whereNull('consumed_at')->update(['consumed_at' => now()]) === 1;
    }

    private function hash(string $phone, string $code): string
    {
        return hash_hmac('sha256', $phone.'|'.$code, (string) config('app.key'));
    }
}
