<?php

namespace App\Enums;

use Filament\Support\Contracts\HasLabel;

enum PaymentMode: string implements HasLabel
{
    case MobileMoney = 'mobile_money';
    case Cash = 'cash';

    public function getLabel(): string
    {
        return $this === self::MobileMoney ? 'Paiement mobile' : 'À la livraison';
    }
}
