<?php

namespace App\Enums;

use Filament\Support\Contracts\HasColor;
use Filament\Support\Contracts\HasLabel;

enum OrderStatus: string implements HasColor, HasLabel
{
    case Received = 'received';
    case PricePending = 'price_pending';
    case Confirmed = 'confirmed';
    case Preparing = 'preparing';
    case Delivering = 'delivering';
    case Delivered = 'delivered';
    case Cancelled = 'cancelled';

    public function getLabel(): string
    {
        return match ($this) {
            self::Received => 'Reçue',
            self::PricePending => 'Prix à valider',
            self::Confirmed => 'Confirmée',
            self::Preparing => 'En préparation',
            self::Delivering => 'En livraison',
            self::Delivered => 'Livrée',
            self::Cancelled => 'Annulée',
        };
    }

    public function getColor(): string
    {
        return match ($this) {
            self::Received, self::PricePending => 'warning',
            self::Confirmed, self::Preparing, self::Delivering => 'info',
            self::Delivered => 'success',
            self::Cancelled => 'danger',
        };
    }

    /** @return list<self> */
    public function nextStatuses(): array
    {
        return match ($this) {
            self::Received => [self::PricePending, self::Cancelled],
            self::PricePending => [self::PricePending, self::Confirmed, self::Received, self::Cancelled],
            self::Confirmed => [self::Preparing, self::Cancelled],
            self::Preparing => [self::Delivering, self::Cancelled],
            self::Delivering => [self::Delivered, self::Cancelled],
            self::Delivered, self::Cancelled => [],
        };
    }

    public function canMoveTo(self $next): bool
    {
        return in_array($next, $this->nextStatuses(), true);
    }

    public function isFinished(): bool
    {
        return $this->nextStatuses() === [];
    }
}
