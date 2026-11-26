<?php

namespace App\Jobs;

use App\Contracts\PushSender;
use App\Models\Message;
use App\Models\User;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;

/** Prévient le destinataire d'un message quand l'application est fermée. */
class SendMessagePush implements ShouldQueue
{
    use Queueable;

    public int $tries = 3;

    public function __construct(public Message $message, public User $recipient) {}

    public function handle(PushSender $push): void
    {
        // Déjà lu dans l'application ouverte : la notification ne servirait à rien.
        if ($this->message->fresh()?->read_at !== null) {
            return;
        }

        $sender = $this->message->sender;
        $title = $sender->business_name ?? $sender->name ?? 'Nouveau message';

        foreach ($this->recipient->deviceTokens()->pluck('token') as $token) {
            $push->send($token, $title, $this->message->type->preview($this->message->body), [
                'kind' => 'message',
                'order_id' => (string) $this->message->order_id,
                'reference' => (string) $this->message->order->reference,
            ]);
        }
    }
}
