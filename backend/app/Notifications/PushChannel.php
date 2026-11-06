<?php

namespace App\Notifications;

use App\Contracts\PushSender;

class PushChannel
{
    public function __construct(private PushSender $push) {}

    public function send(object $notifiable, AppEvent $notification): void
    {
        foreach ($notifiable->deviceTokens()->pluck('token') as $token) {
            $this->push->send($token, $notification->title, $notification->body, array_filter([
                'order_id' => $notification->order ? (string) $notification->order->id : null,
            ]));
        }
    }
}
