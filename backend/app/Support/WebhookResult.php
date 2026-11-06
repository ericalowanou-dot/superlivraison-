<?php

namespace App\Support;

final readonly class WebhookResult
{
    public function __construct(
        public string $paymentReference,
        public bool $succeeded,
        public int $amount,
        public ?string $providerReference = null,
        public ?string $failureReason = null,
    ) {}
}
