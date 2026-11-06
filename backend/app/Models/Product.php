<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\Storage;

class Product extends Model
{
    protected $fillable = ['shop_id', 'name', 'description', 'price', 'stock', 'image_path', 'is_active'];

    protected $attributes = ['is_active' => true];

    protected function casts(): array
    {
        return [
            'price' => 'integer',
            'stock' => 'integer',
            'is_active' => 'boolean',
        ];
    }

    protected static function booted(): void
    {
        static::deleted(fn (Product $product) => Storage::disk(config('superlivraison.media_disk'))->delete($product->image_path));
    }

    public function shop(): BelongsTo
    {
        return $this->belongsTo(Shop::class);
    }
}
