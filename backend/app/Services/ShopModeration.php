<?php

namespace App\Services;

use App\Enums\ReviewStatus;
use App\Enums\Role;
use App\Models\Shop;
use App\Models\User;
use App\Notifications\AppEvent;
use Illuminate\Support\Facades\Notification;

/** Une boutique créée depuis l'application n'est visible qu'après validation par l'équipe. */
class ShopModeration
{
    public function submitted(Shop $shop): void
    {
        Notification::send(
            User::whereIn('role', [Role::Operator, Role::Admin])->where('is_active', true)->get(),
            new AppEvent('Boutique à valider', "« {$shop->name} » attend une validation."),
        );
    }

    public function approve(Shop $shop): void
    {
        $shop->forceFill(['status' => ReviewStatus::Approved, 'approved_at' => now(), 'rejection_reason' => null])->save();

        $shop->owner?->notify(new AppEvent('Boutique validée', "« {$shop->name} » est maintenant ouverte."));
    }

    public function reject(Shop $shop, string $reason): void
    {
        $shop->forceFill(['status' => ReviewStatus::Rejected, 'approved_at' => null, 'rejection_reason' => $reason])->save();

        $shop->owner?->notify(new AppEvent('Boutique refusée', "« {$shop->name} » : {$reason}"));
    }
}
