<?php

namespace App\Support;

class Phone
{
    /** Numéro au format international (+22890000000), ou null s'il est invalide. */
    public static function normalize(?string $value): ?string
    {
        $phone = preg_replace('/[\s().-]/', '', (string) $value);

        return preg_match('/^\+[1-9]\d{7,14}$/', (string) $phone) ? $phone : null;
    }
}
