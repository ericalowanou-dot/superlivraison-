<?php

namespace App\Services;

use App\Contracts\PaymentGateway;
use App\Enums\OrderStatus;
use App\Enums\PaymentMethod;
use App\Enums\PaymentMode;
use App\Enums\PaymentStatus;
use App\Exceptions\WorkflowException;
use App\Models\Order;
use App\Models\Payment;
use App\Models\User;
use App\Notifications\AppEvent;
use App\Support\WebhookResult;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class PaymentService
{
    public function __construct(private PaymentGateway $gateway) {}

    public function startMobile(Order $order, User $user, PaymentMethod $method, string $phone): Payment
    {
        if ($method === PaymentMethod::Cash) {
            throw new WorkflowException('Choisissez un moyen de paiement mobile.');
        }

        $payment = DB::transaction(function () use ($order, $user, $method, $phone) {
            $locked = Order::lockForUpdate()->findOrFail($order->id);

            if ($locked->isPaid()) {
                throw new WorkflowException('Cette commande est déjà payée.');
            }

            if ($locked->status !== OrderStatus::Confirmed || $locked->payment_mode !== PaymentMode::MobileMoney) {
                throw new WorkflowException('Cette commande n\'attend pas de paiement mobile.');
            }

            $recent = $locked->payments()
                ->where('status', PaymentStatus::Pending)
                ->where('created_at', '>', now()->subMinutes((int) config('superlivraison.payment_pending_minutes')))
                ->exists();

            if ($recent) {
                throw new WorkflowException('Un paiement est déjà en cours pour cette commande.');
            }

            return Payment::create([
                'reference' => (string) Str::uuid(),
                'order_id' => $locked->id,
                'user_id' => $user->id,
                'amount' => $locked->price,
                'currency' => $locked->currency,
                'method' => $method,
                'provider' => $this->gateway->name(),
                'payer_phone' => $phone,
            ]);
        });

        // Hors transaction : l'appel réseau ne doit pas garder la commande verrouillée.
        $result = $this->gateway->charge($payment);

        $payment->forceFill($result->accepted
            ? ['provider_reference' => $result->providerReference]
            : ['status' => PaymentStatus::Failed, 'failure_reason' => $result->failureReason]
        )->save();

        return $payment;
    }

    /** Applique un webhook. Il peut arriver plusieurs fois : seul le premier change quelque chose. */
    public function applyWebhook(WebhookResult $event): void
    {
        $notify = DB::transaction(function () use ($event) {
            $payment = Payment::where('reference', $event->paymentReference)
                ->where('provider', $this->gateway->name())
                ->lockForUpdate()
                ->first();

            if (! $payment) {
                Log::warning('Webhook de paiement inconnu', ['reference' => $event->paymentReference]);

                return null;
            }

            if ($payment->status === PaymentStatus::Succeeded || $payment->status === PaymentStatus::Refunded) {
                return null;
            }

            if ($event->providerReference) {
                $payment->provider_reference = $event->providerReference;
            }

            if (! $event->succeeded) {
                $payment->status = PaymentStatus::Failed;
                $payment->failure_reason = $event->failureReason;
                $payment->save();

                return $payment;
            }

            if ($event->amount !== $payment->amount) {
                $payment->needs_review = true;
                $payment->failure_reason = "Montant reçu : {$event->amount} FCFA";
                $payment->save();

                return null;
            }

            $order = Order::lockForUpdate()->findOrFail($payment->order_id);
            $payment->status = PaymentStatus::Succeeded;
            $payment->paid_at = now();

            // Double paiement ou commande annulée entre-temps : l'argent est reçu, un humain tranche.
            if ($order->isPaid() || $order->status === OrderStatus::Cancelled) {
                $payment->needs_review = true;
            } else {
                $order->paid_at = now();
                $order->save();
            }

            $payment->save();

            return $payment;
        });

        if ($notify) {
            $this->notifyResult($notify);
        }
    }

    public function registerCash(Order $order): Payment
    {
        return Payment::create([
            'reference' => (string) Str::uuid(),
            'order_id' => $order->id,
            'user_id' => $order->restaurant_id,
            'amount' => $order->price,
            'currency' => $order->currency,
            'method' => PaymentMethod::Cash,
        ]);
    }

    public function confirmCash(Order $order): void
    {
        DB::transaction(function () use ($order) {
            $locked = Order::lockForUpdate()->findOrFail($order->id);
            $payment = $locked->payments()->where('method', PaymentMethod::Cash)->where('status', PaymentStatus::Pending)->first();

            if ($payment) {
                $payment->forceFill(['status' => PaymentStatus::Succeeded, 'paid_at' => now()])->save();
                $locked->forceFill(['paid_at' => now()])->save();
            }
        });
    }

    /** Une commande annulée ne doit plus laisser de paiement en attente. */
    public function closePending(Order $order): void
    {
        $order->payments()
            ->where('status', PaymentStatus::Pending)
            ->where('method', PaymentMethod::Cash)
            ->update(['status' => PaymentStatus::Failed, 'failure_reason' => 'Commande annulée']);
    }

    public function refund(Payment $payment, User $admin): Payment
    {
        return DB::transaction(function () use ($payment, $admin) {
            $locked = Payment::lockForUpdate()->findOrFail($payment->id);

            if ($locked->status !== PaymentStatus::Succeeded) {
                throw new WorkflowException('Seul un paiement réussi peut être remboursé.');
            }

            if ($locked->method !== PaymentMethod::Cash && ! $this->gateway->refund($locked)) {
                throw new WorkflowException('L\'agrégateur a refusé le remboursement.');
            }

            $locked->forceFill([
                'status' => PaymentStatus::Refunded,
                'refunded_at' => now(),
                'refunded_by' => $admin->id,
                'needs_review' => false,
            ])->save();

            return $locked;
        });
    }

    private function notifyResult(Payment $payment): void
    {
        $order = $payment->order;
        [$title, $body] = $payment->status === PaymentStatus::Succeeded
            ? ['Paiement réussi', "{$payment->amount} FCFA reçus pour {$order->reference}."]
            : ['Paiement échoué', "Le paiement de {$order->reference} n'a pas abouti."];

        $payment->user->notify(new AppEvent($title, $body, $order));
    }
}
