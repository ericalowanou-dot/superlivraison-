<?php

namespace App\Contracts;

interface PushSender
{
    /** @param array<string, string> $data */
    public function send(string $token, string $title, string $body, array $data = []): void;

    /**
     * Message silencieux traité par l'appli elle-même, par exemple pour faire sonner un appel.
     *
     * @param  array<string, string>  $data
     */
    public function sendData(string $token, array $data, int $ttlSeconds = 60): void;
}
