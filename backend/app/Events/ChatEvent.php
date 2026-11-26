<?php

namespace App\Events;

use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;

/**
 * Un évènement de la discussion d'une course, envoyé tout de suite aux téléphones connectés.
 * Le canal privé « orders.{id} » n'est ouvert qu'au client et au livreur de la course.
 */
class ChatEvent implements ShouldBroadcastNow
{
    /** @param array<string, mixed> $payload */
    public function __construct(
        public int $orderId,
        public string $name,
        public array $payload,
    ) {}

    public function broadcastOn(): PrivateChannel
    {
        return new PrivateChannel('orders.'.$this->orderId);
    }

    public function broadcastAs(): string
    {
        return $this->name;
    }

    /** @return array<string, mixed> */
    public function broadcastWith(): array
    {
        return $this->payload;
    }
}
