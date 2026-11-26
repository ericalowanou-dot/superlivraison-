<?php

namespace App\Models;

use App\Enums\CallStatus;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Un appel audio ou vidéo entre le client et le livreur d'une course. */
class Call extends Model
{
    protected $fillable = ['caller_id', 'callee_id', 'video', 'status', 'answered_at', 'ended_at'];

    protected function casts(): array
    {
        return [
            'video' => 'boolean',
            'status' => CallStatus::class,
            'answered_at' => 'datetime',
            'ended_at' => 'datetime',
        ];
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }

    public function caller(): BelongsTo
    {
        return $this->belongsTo(User::class, 'caller_id')->withTrashed();
    }

    public function callee(): BelongsTo
    {
        return $this->belongsTo(User::class, 'callee_id')->withTrashed();
    }

    public function involves(User $user): bool
    {
        return $user->id === $this->caller_id || $user->id === $this->callee_id;
    }

    /** Durée de la conversation, une fois l'appel décroché. */
    public function durationSeconds(): ?int
    {
        if ($this->answered_at === null) {
            return null;
        }

        return (int) $this->answered_at->diffInSeconds($this->ended_at ?? now(), true);
    }

    /** Nom de la salle ZEGOCLOUD : lettres, chiffres et « _ » seulement. */
    public function roomId(): string
    {
        return 'call_'.$this->id;
    }

    public static function zegoUserId(int $userId): string
    {
        return 'u'.$userId;
    }

    public function streamId(int $userId): string
    {
        return $this->roomId().'_'.self::zegoUserId($userId);
    }
}
