<?php

namespace App\Contracts;

interface Transcriber
{
    /** Retourne le texte du fichier audio, stocké sur le disque « media ». */
    public function transcribe(string $path, string $language): string;
}
