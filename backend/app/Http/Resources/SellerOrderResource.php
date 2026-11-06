<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** Ce que voit le vendeur : les articles à préparer, sans les coordonnées du client. */
class SellerOrderResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'reference' => $this->reference,
            'status' => $this->status,
            'status_label' => $this->status->getLabel(),
            'goods_total' => $this->goods_total,
            'created_at' => $this->created_at,
            'items' => $this->items->map(fn ($item) => [
                'name' => $item->name,
                'unit_price' => $item->unit_price,
                'quantity' => $item->quantity,
            ]),
        ];
    }
}
