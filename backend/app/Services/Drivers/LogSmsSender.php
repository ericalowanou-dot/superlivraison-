<?php

namespace App\Services\Drivers;

use App\Contracts\SmsSender;
use Illuminate\Support\Facades\Log;

/** Développement seulement : le SMS est écrit dans le journal. */
class LogSmsSender implements SmsSender
{
    public function send(string $phone, string $message): void
    {
        Log::info('SMS simulé', ['phone' => $phone, 'message' => $message]);
    }
}
