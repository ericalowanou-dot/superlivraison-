<?php

namespace App\Enums;

use Filament\Support\Contracts\HasLabel;

enum OrderChannel: string implements HasLabel
{
    case Text = 'text';
    case Voice = 'voice';
    case Courier = 'courier';

    public function getLabel(): string
    {
        return match ($this) {
            self::Text => 'Message',
            self::Voice => 'Vocal',
            self::Courier => 'Course livreur',
        };
    }
}
