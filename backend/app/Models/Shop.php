<?php

namespace App\Models;

use App\Enums\ReviewStatus;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Facades\Storage;

class Shop extends Model
{
    // Le statut ne passe que par ShopModeration.
    protected $fillable = ['owner_id', 'city_id', 'name', 'category', 'description', 'phone', 'landmark', 'lat', 'lng', 'image_path', 'is_active'];

    protected $attributes = ['status' => 'pending', 'is_active' => true];

    protected function casts(): array
    {
        return [
            'lat' => 'float',
            'lng' => 'float',
            'is_active' => 'boolean',
            'status' => ReviewStatus::class,
            'approved_at' => 'datetime',
        ];
    }

    protected static function booted(): void
    {
        static::deleted(function (Shop $shop): void {
            if ($shop->image_path !== null) {
                Storage::disk(config('superlivraison.media_disk'))->delete($shop->image_path);
            }
        });
    }

    public function owner(): BelongsTo
    {
        return $this->belongsTo(User::class, 'owner_id')->withTrashed();
    }

    public function city(): BelongsTo
    {
        return $this->belongsTo(City::class);
    }

    public function products(): HasMany
    {
        return $this->hasMany(Product::class);
    }

    public function orders(): HasMany
    {
        return $this->hasMany(Order::class);
    }

    public function payouts(): HasMany
    {
        return $this->hasMany(Payout::class);
    }

    public function isOpen(): bool
    {
        return $this->is_active && $this->status === ReviewStatus::Approved;
    }

    /** @param Builder<Shop> $query */
    public function scopeOpen(Builder $query): void
    {
        $query->where('is_active', true)->where('status', ReviewStatus::Approved);
    }
}
