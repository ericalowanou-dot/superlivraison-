<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\Storage;

class Shop extends Model
{
    protected $fillable = ['city_id', 'name', 'category', 'description', 'phone', 'landmark', 'lat', 'lng', 'image_path', 'is_active'];

    protected function casts(): array
    {
        return [
            'lat' => 'float',
            'lng' => 'float',
            'is_active' => 'boolean',
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

    public function city(): BelongsTo
    {
        return $this->belongsTo(City::class);
    }

    /** @param Builder<Shop> $query */
    public function scopeActive(Builder $query): void
    {
        $query->where('is_active', true);
    }
}
