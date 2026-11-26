<?php

namespace App\Models;

use App\Enums\MessageType;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Un message de la discussion entre le client et le livreur d'une course. */
class Message extends Model
{
    protected $fillable = ['client_uuid', 'sender_id', 'call_id', 'type', 'body', 'path', 'duration_seconds', 'lat', 'lng'];

    protected function casts(): array
    {
        return [
            'type' => MessageType::class,
            'duration_seconds' => 'integer',
            'lat' => 'float',
            'lng' => 'float',
            'delivered_at' => 'datetime',
            'read_at' => 'datetime',
        ];
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }

    public function call(): BelongsTo
    {
        return $this->belongsTo(Call::class);
    }

    public function sender(): BelongsTo
    {
        return $this->belongsTo(User::class, 'sender_id')->withTrashed();
    }
}
