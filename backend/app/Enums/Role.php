<?php

namespace App\Enums;

use Filament\Support\Contracts\HasLabel;

enum Role: string implements HasLabel
{
    case Restaurant = 'restaurant';
    case Courier = 'courier';
    case Operator = 'operator';
    case Admin = 'admin';

    public function getLabel(): string
    {
        return match ($this) {
            self::Restaurant => 'Restaurant',
            self::Courier => 'Livreur',
            self::Operator => 'Opérateur',
            self::Admin => 'Administrateur',
        };
    }

    public function isStaff(): bool
    {
        return in_array($this, [self::Operator, self::Admin], true);
    }
}
