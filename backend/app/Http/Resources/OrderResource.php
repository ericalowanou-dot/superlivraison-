<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class OrderResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'reference' => $this->reference,
            'channel' => $this->channel,
            'request_text' => $this->request_text,
            'has_voice' => $this->voice_note_id !== null,
            'delivery' => [
                'lat' => $this->delivery_lat,
                'lng' => $this->delivery_lng,
                'landmark' => $this->delivery_landmark,
                'recipient_phone' => $this->recipient_phone,
            ],
            'status' => $this->status,
            'status_label' => $this->status->getLabel(),
            'price' => $this->price,
            'currency' => $this->currency,
            'payment_mode' => $this->payment_mode,
            'is_paid' => $this->isPaid(),
            'cancel_reason' => $this->cancel_reason,
            'priced_at' => $this->priced_at,
            'delivered_at' => $this->delivered_at,
            'created_at' => $this->created_at,
            'events' => $this->whenLoaded('events', fn () => $this->events->map(fn ($e) => [
                'status' => $e->to_status,
                'status_label' => $e->to_status->getLabel(),
                'at' => $e->created_at,
            ])),
        ];
    }
}
