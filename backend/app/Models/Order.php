<?php

namespace App\Models;

use App\Enums\OrderChannel;
use App\Enums\OrderStatus;
use App\Enums\PaymentMode;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Order extends Model
{
    // Le statut, le prix et le livreur ne passent que par OrderWorkflow.
    protected $fillable = ['client_uuid', 'restaurant_id', 'city_id', 'voice_note_id', 'channel', 'request_text', 'delivery_lat', 'delivery_lng', 'delivery_landmark', 'recipient_phone', 'shop_id', 'goods_total'];

    protected $attributes = ['status' => 'received'];

    protected function casts(): array
    {
        return [
            'status' => OrderStatus::class,
            'channel' => OrderChannel::class,
            'payment_mode' => PaymentMode::class,
            'price' => 'integer',
            'goods_total' => 'integer',
            'delivery_fee' => 'integer',
            'delivery_lat' => 'float',
            'delivery_lng' => 'float',
            'priced_at' => 'datetime',
            'confirmed_at' => 'datetime',
            'paid_at' => 'datetime',
            'delivered_at' => 'datetime',
        ];
    }

    protected static function booted(): void
    {
        static::created(function (Order $order): void {
            $order->forceFill(['reference' => 'CMD-'.(1000 + $order->id)])->saveQuietly();
        });
    }

    public function restaurant(): BelongsTo
    {
        return $this->belongsTo(User::class, 'restaurant_id')->withTrashed();
    }

    public function shop(): BelongsTo
    {
        return $this->belongsTo(Shop::class);
    }

    public function items(): HasMany
    {
        return $this->hasMany(OrderItem::class);
    }

    public function courier(): BelongsTo
    {
        return $this->belongsTo(User::class, 'courier_id')->withTrashed();
    }

    public function city(): BelongsTo
    {
        return $this->belongsTo(City::class);
    }

    public function voiceNote(): BelongsTo
    {
        return $this->belongsTo(VoiceNote::class);
    }

    public function events(): HasMany
    {
        return $this->hasMany(OrderEvent::class)->latest('id');
    }

    public function payments(): HasMany
    {
        return $this->hasMany(Payment::class);
    }

    public function isPaid(): bool
    {
        return $this->paid_at !== null;
    }
}
