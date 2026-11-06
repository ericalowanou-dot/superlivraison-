<?php

namespace App\Services\Drivers;

use App\Contracts\Transcriber;

/** Développement seulement : aucun appel au service de retranscription. */
class FakeTranscriber implements Transcriber
{
    public function transcribe(string $path, string $language): string
    {
        return 'Retranscription simulée du vocal.';
    }
}
