<?php

namespace App\Services\Drivers;

use App\Contracts\PushSender;
use Illuminate\Support\Facades\Log;

/** Développement seulement : la notification est écrite dans le journal. */
class LogPushSender implements PushSender
{
    public function send(string $token, string $title, string $body, array $data = []): void
    {
        Log::info('Notification simulée', compact('title', 'body', 'data'));
    }
}
