<?php

namespace App\Providers;

use App\Contracts\PaymentGateway;
use App\Contracts\PushSender;
use App\Contracts\SmsSender;
use App\Contracts\Transcriber;
use App\Services\Drivers\FakePaymentGateway;
use App\Services\Drivers\FakeTranscriber;
use App\Services\Drivers\LogPushSender;
use App\Services\Drivers\LogSmsSender;
use App\Support\Phone;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\URL;
use Illuminate\Support\ServiceProvider;
use RuntimeException;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(SmsSender::class, fn () => match ($this->driver('sms_driver')) {
            'log' => new LogSmsSender,
            default => throw new RuntimeException('Fournisseur SMS inconnu.'),
        });

        $this->app->singleton(PushSender::class, fn () => match ($this->driver('push_driver')) {
            'log' => new LogPushSender,
            default => throw new RuntimeException('Fournisseur de notifications inconnu.'),
        });

        $this->app->singleton(Transcriber::class, fn () => match ($this->driver('transcriber_driver')) {
            'fake' => new FakeTranscriber,
            default => throw new RuntimeException('Service de retranscription inconnu.'),
        });

        $this->app->singleton(PaymentGateway::class, fn () => match ($this->driver('payment_driver')) {
            'fake' => new FakePaymentGateway((string) config('superlivraison.fake_payment_secret')),
            default => throw new RuntimeException('Agrégateur de paiement inconnu.'),
        });
    }

    public function boot(): void
    {
        JsonResource::withoutWrapping();

        if ($this->app->isProduction()) {
            URL::forceScheme('https');
        }

        // Chaque SMS coûte de l'argent : les envois sont limités par numéro et par adresse IP.
        RateLimiter::for('otp-request', function (Request $request) {
            $phone = Phone::normalize($request->input('phone')) ?? 'invalide';

            return [
                Limit::perMinute(1)->by('otp-minute:'.$phone),
                Limit::perHour(5)->by('otp-hour:'.$phone),
                Limit::perHour(20)->by('otp-ip:'.$request->ip()),
            ];
        });

        RateLimiter::for('otp-verify', fn (Request $request) => Limit::perMinute(10)->by('otp-verify:'.$request->ip()));

        RateLimiter::for('api', fn (Request $request) => Limit::perMinute(120)->by($request->user()?->id ?: $request->ip()));
    }

    private function driver(string $key): string
    {
        $driver = (string) config('superlivraison.'.$key);

        if ($this->app->isProduction() && in_array($driver, ['log', 'fake'], true)) {
            throw new RuntimeException("Le service de simulation « {$driver} » est interdit en production ({$key}).");
        }

        return $driver;
    }
}
