<?php

namespace App\Models;

use App\Enums\VoiceNoteStatus;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class VoiceNote extends Model
{
    protected $fillable = ['user_id', 'path', 'duration_seconds', 'status', 'transcript'];

    protected $casts = ['status' => VoiceNoteStatus::class];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
