<?php

namespace App\Enums;

enum CallStatus: string
{
    /** Le téléphone de l'autre personne sonne. */
    case Ringing = 'ringing';
    /** Les deux personnes se parlent. */
    case Ongoing = 'ongoing';
    /** Appel décroché puis raccroché. */
    case Ended = 'ended';
    /** Refusé par la personne appelée. */
    case Declined = 'declined';
    /** Sans réponse, ou annulé avant d'être décroché. */
    case Missed = 'missed';

    public function isActive(): bool
    {
        return $this === self::Ringing || $this === self::Ongoing;
    }
}
