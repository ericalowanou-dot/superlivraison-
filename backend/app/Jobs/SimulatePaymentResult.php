<?php

namespace App\Jobs;

use App\Enums\PaymentStatus;
use App\Models\Payment;
use App\Services\PaymentService;
use App\Support\WebhookResult;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;

/**
 * Développement seulement : joue le rôle de l'opérateur de paiement mobile
 * en renvoyant le résultat, comme le ferait son webhook.
 */
class SimulatePaymentResult implements ShouldQueue
{
    use Queueable;

    public function __construct(public int $paymentId, public bool $succeeded) {}

    public function handle(PaymentService $payments): void
    {
        $payment = Payment::find($this->paymentId);
        if ($payment === null || $payment->status !== PaymentStatus::Pending) {
            return;
        }

        $payments->applyWebhook(new WebhookResult(
            paymentReference: $payment->reference,
            succeeded: $this->succeeded,
            amount: $payment->amount,
            providerReference: 'simulation-'.$payment->id,
            failureReason: $this->succeeded ? null : 'Paiement refusé (simulation).',
        ));
    }
}
