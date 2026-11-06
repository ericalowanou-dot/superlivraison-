<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class PaymentResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'order_id' => $this->order_id,
            'order_reference' => $this->whenLoaded('order', fn () => $this->order->reference),
            'amount' => $this->amount,
            'currency' => $this->currency,
            'method' => $this->method,
            'method_label' => $this->method->getLabel(),
            'status' => $this->status,
            'status_label' => $this->status->getLabel(),
            'failure_reason' => $this->failure_reason,
            'paid_at' => $this->paid_at,
            'created_at' => $this->created_at,
        ];
    }
}
