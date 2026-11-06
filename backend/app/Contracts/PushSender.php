<?php

namespace App\Contracts;

interface PushSender
{
    /** @param array<string, string> $data */
    public function send(string $token, string $title, string $body, array $data = []): void;
}
