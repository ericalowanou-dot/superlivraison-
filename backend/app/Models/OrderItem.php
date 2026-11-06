<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Copie de l'article au moment de l'achat : son nom et son prix ne changent plus ensuite. */
class OrderItem extends Model
{
    protected $fillable = ['order_id', 'product_id', 'name', 'unit_price', 'quantity'];

    protected function casts(): array
    {
        return [
            'unit_price' => 'integer',
            'quantity' => 'integer',
        ];
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }
}
