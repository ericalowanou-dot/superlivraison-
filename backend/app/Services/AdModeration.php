<?php

namespace App\Services;

use App\Enums\ReviewStatus;
use App\Enums\Role;
use App\Models\Ad;
use App\Models\User;
use App\Notifications\AppEvent;
use Illuminate\Support\Facades\Notification;

/** Une publicité envoyée depuis l'application n'est visible qu'après validation par l'équipe. */
class AdModeration
{
    public function submitted(Ad $ad): void
    {
        Notification::send(
            User::whereIn('role', [Role::Operator, Role::Admin])->where('is_active', true)->get(),
            new AppEvent('Publicité à valider', "« {$ad->title} » attend une validation."),
        );
    }

    public function approve(Ad $ad): void
    {
        $ad->forceFill(['status' => ReviewStatus::Approved, 'approved_at' => now(), 'rejection_reason' => null])->save();

        $ad->user?->notify(new AppEvent('Publicité publiée', "« {$ad->title} » est maintenant visible."));
    }

    public function reject(Ad $ad, string $reason): void
    {
        $ad->forceFill(['status' => ReviewStatus::Rejected, 'approved_at' => null, 'rejection_reason' => $reason])->save();

        $ad->user?->notify(new AppEvent('Publicité refusée', "« {$ad->title} » : {$reason}"));
    }
}
