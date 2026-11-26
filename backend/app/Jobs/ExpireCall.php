<?php

namespace App\Jobs;

use App\Models\Call;
use App\Services\Calls;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;

/** Un appel resté sans réponse est noté comme manqué. */
class ExpireCall implements ShouldQueue
{
    use Queueable;

    public function __construct(public int $callId) {}

    public function handle(Calls $calls): void
    {
        $call = Call::find($this->callId);
        if ($call !== null) {
            $calls->expire($call);
        }
    }
}
