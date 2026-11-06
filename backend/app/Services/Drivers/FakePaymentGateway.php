<?php

namespace App\Services\Drivers;

use App\Contracts\PaymentGateway;
use App\Models\Payment;
use App\Support\ChargeResult;
use App\Support\WebhookResult;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

/**
 * Développement seulement. Reproduit le fonctionnement d'un agrégateur :
 * la demande reste en attente jusqu'au webhook signé qui donne le résultat.
 */
class FakePaymentGateway implements PaymentGateway
{
    public function __construct(private string $secret) {}

    public function name(): string
    {
        return 'fake';
    }

    public function charge(Payment $payment): ChargeResult
    {
        return new ChargeResult(true, 'fake-'.Str::uuid());
    }

    public function parseWebhook(Request $request): ?WebhookResult
    {
        $expected = hash_hmac('sha256', $request->getContent(), $this->secret);

        if (! hash_equals($expected, (string) $request->header('X-Signature'))) {
            return null;
        }

        return new WebhookResult(
            paymentReference: (string) $request->input('reference'),
            succeeded: $request->input('status') === 'success',
            amount: (int) $request->input('amount'),
            providerReference: $request->input('provider_reference'),
            failureReason: $request->input('reason'),
        );
    }

    public function refund(Payment $payment): bool
    {
        return true;
    }
}
