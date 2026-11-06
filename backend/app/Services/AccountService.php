<?php

namespace App\Services;

use App\Enums\OrderStatus;
use App\Enums\PaymentStatus;
use App\Exceptions\WorkflowException;
use App\Models\Order;
use App\Models\Payment;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

class AccountService
{
    /**
     * Supprime le compte (E6). Les commandes restent pour la comptabilité,
     * sans les données personnelles du compte.
     */
    public function delete(User $user): void
    {
        $open = Order::where('restaurant_id', $user->id)
            ->whereNotIn('status', [OrderStatus::Delivered, OrderStatus::Cancelled])
            ->exists();
        $pending = Payment::where('user_id', $user->id)->where('status', PaymentStatus::Pending)->exists();

        if ($open || $pending) {
            throw new WorkflowException('Terminez ou annulez vos commandes en cours avant de supprimer le compte.');
        }

        $paths = $user->voiceNotes()->pluck('path')->all();

        DB::transaction(function () use ($user) {
            $user->tokens()->delete();
            $user->deviceTokens()->delete();
            $user->notifications()->delete();
            $user->voiceNotes()->delete();
            $user->forceFill([
                'phone' => null,
                'name' => null,
                'business_name' => null,
                'email' => null,
                'password' => null,
                'is_active' => false,
            ])->save();
            $user->delete();
        });

        Storage::disk(config('superlivraison.media_disk'))->delete($paths);
    }
}
