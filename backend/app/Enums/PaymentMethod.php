<?php

namespace App\Enums;

use Filament\Support\Contracts\HasLabel;

enum PaymentMethod: string implements HasLabel
{
    case Mixx = 'mixx';
    case Flooz = 'flooz';
    case Cash = 'cash';

    public function getLabel(): string
    {
        return match ($this) {
            self::Mixx => 'Mixx by Yas',
            self::Flooz => 'Flooz',
            self::Cash => 'Espèces à la livraison',
        };
    }
}
