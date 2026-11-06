<?php

namespace App\Models;

use App\Enums\AdCategory;
use App\Enums\AdStatus;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\Storage;

class Ad extends Model
{
    // Le statut ne passe que par AdModeration.
    protected $fillable = ['user_id', 'city_id', 'category', 'title', 'description', 'image_path'];

    protected $attributes = ['status' => 'pending'];

    protected function casts(): array
    {
        return [
            'category' => AdCategory::class,
            'status' => AdStatus::class,
            'approved_at' => 'datetime',
        ];
    }

    protected static function booted(): void
    {
        static::deleted(fn (Ad $ad) => Storage::disk(config('superlivraison.media_disk'))->delete($ad->image_path));
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class)->withTrashed();
    }

    public function city(): BelongsTo
    {
        return $this->belongsTo(City::class);
    }

    /** @param Builder<Ad> $query */
    public function scopeApproved(Builder $query): void
    {
        $query->where('status', AdStatus::Approved);
    }
}
