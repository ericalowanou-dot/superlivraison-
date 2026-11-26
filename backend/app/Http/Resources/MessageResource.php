<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class MessageResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'order_id' => $this->order_id,
            'client_uuid' => $this->client_uuid,
            'sender_id' => $this->sender_id,
            'type' => $this->type,
            'body' => $this->body,
            'has_media' => $this->path !== null,
            'duration_seconds' => $this->duration_seconds,
            'lat' => $this->lat,
            'lng' => $this->lng,
            'delivered_at' => $this->delivered_at,
            'read_at' => $this->read_at,
            'created_at' => $this->created_at,
        ];
    }
}
