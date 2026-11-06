<?php

namespace App\Notifications;

use App\Models\Order;
use Filament\Notifications\Notification as PanelNotification;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Notification;

/** Une notification de l'application : historique, administration et notification du téléphone. */
class AppEvent extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(
        public string $title,
        public string $body,
        public ?Order $order = null,
    ) {}

    /** @return list<string> */
    public function via(object $notifiable): array
    {
        return ['database', PushChannel::class];
    }

    /** @return array<string, mixed> */
    public function toArray(object $notifiable): array
    {
        return [
            ...PanelNotification::make()->title($this->title)->body($this->body)->getDatabaseMessage(),
            'order_id' => $this->order?->id,
        ];
    }
}
