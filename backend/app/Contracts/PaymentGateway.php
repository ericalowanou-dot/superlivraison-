<?php

namespace App\Contracts;

use App\Models\Payment;
use App\Support\ChargeResult;
use App\Support\WebhookResult;
use Illuminate\Http\Request;

interface PaymentGateway
{
    public function name(): string;

    /** Lance la demande de paiement auprès de l'agrégateur. */
    public function charge(Payment $payment): ChargeResult;

    /** Lit un webhook, ou retourne null si sa signature est invalide. */
    public function parseWebhook(Request $request): ?WebhookResult;

    public function refund(Payment $payment): bool;
}
