<?php

namespace App\Enums;

use Filament\Support\Contracts\HasLabel;

enum AdCategory: string implements HasLabel
{
    case Advert = 'advert';
    case Concert = 'concert';
    case Other = 'other';

    public function getLabel(): string
    {
        return match ($this) {
            self::Advert => 'Publicité',
            self::Concert => 'Concert',
            self::Other => 'Autre',
        };
    }
}
