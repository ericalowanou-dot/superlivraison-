<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class PayoutResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'order_reference' => $this->order?->reference,
            'goods_total' => $this->goods_total,
            'commission' => $this->commission,
            'amount' => $this->amount,
            'status' => $this->status,
            'status_label' => $this->status->getLabel(),
            'paid_at' => $this->paid_at,
            'created_at' => $this->created_at,
        ];
    }
}
