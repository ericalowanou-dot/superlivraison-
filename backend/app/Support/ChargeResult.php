<?php

namespace App\Support;

final readonly class ChargeResult
{
    public function __construct(
        public bool $accepted,
        public ?string $providerReference = null,
        public ?string $failureReason = null,
    ) {}
}
