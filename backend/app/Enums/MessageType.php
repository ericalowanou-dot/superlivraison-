<?php

namespace App\Enums;

enum MessageType: string
{
    case Text = 'text';
    case Voice = 'voice';
    case Image = 'image';
    case Location = 'location';
    case Call = 'call';

    /** Le résumé affiché dans la notification du téléphone. */
    public function preview(?string $body): string
    {
        return match ($this) {
            self::Text => mb_strimwidth((string) $body, 0, 120, '…'),
            self::Voice => 'Message vocal',
            self::Image => 'Photo',
            self::Location => 'Position partagée',
            self::Call => 'Appel',
        };
    }
}
