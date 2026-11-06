<?php

namespace App\Enums;

use Filament\Support\Contracts\HasLabel;

enum OrderChannel: string implements HasLabel
{
    case Text = 'text';
    case Voice = 'voice';

    public function getLabel(): string
    {
        return $this === self::Text ? 'Message' : 'Vocal';
    }
}
