<?php

namespace App\Models;

use App\Enums\PayoutStatus;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Ce que la plateforme doit au vendeur pour une commande livrée. */
class Payout extends Model
{
    // Les montants et le statut ne passent que par ShopPayouts.
    protected $fillable = ['shop_id', 'order_id', 'goods_total', 'commission', 'amount'];

    protected $attributes = ['status' => 'pending'];

    protected function casts(): array
    {
        return [
            'goods_total' => 'integer',
            'commission' => 'integer',
            'amount' => 'integer',
            'status' => PayoutStatus::class,
            'paid_at' => 'datetime',
        ];
    }

    public function shop(): BelongsTo
    {
        return $this->belongsTo(Shop::class);
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }
}
