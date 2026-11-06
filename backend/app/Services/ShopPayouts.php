<?php

namespace App\Services;

use App\Enums\OrderChannel;
use App\Enums\PayoutStatus;
use App\Exceptions\WorkflowException;
use App\Models\Order;
use App\Models\Payout;
use App\Notifications\AppEvent;

/** La plateforme encaisse, garde sa commission sur les articles et reverse le reste après livraison. */
class ShopPayouts
{
    public function record(Order $order): ?Payout
    {
        if ($order->channel !== OrderChannel::Shop || $order->shop === null) {
            return null;
        }

        $commission = (int) round($order->goods_total * config('superlivraison.shop_commission_percent') / 100);

        $payout = Payout::firstOrCreate(['order_id' => $order->id], [
            'shop_id' => $order->shop_id,
            'goods_total' => $order->goods_total,
            'commission' => $commission,
            'amount' => $order->goods_total - $commission,
        ]);

        if ($payout->wasRecentlyCreated) {
            $order->shop->owner?->notify(new AppEvent('Commande livrée', "{$order->reference} : {$payout->amount} FCFA à recevoir."));
        }

        return $payout;
    }

    public function markPaid(Payout $payout, string $reference): void
    {
        if ($payout->status !== PayoutStatus::Pending) {
            throw new WorkflowException('Ce reversement est déjà traité.');
        }

        $payout->forceFill(['status' => PayoutStatus::Paid, 'reference' => $reference, 'paid_at' => now()])->save();

        $payout->shop->owner?->notify(new AppEvent('Reversement effectué', "{$payout->amount} FCFA ont été envoyés."));
    }

    /** Un client remboursé n'ouvre plus droit au reversement, s'il n'est pas déjà parti. */
    public function cancelFor(Order $order): void
    {
        Payout::where('order_id', $order->id)->where('status', PayoutStatus::Pending)->update(['status' => PayoutStatus::Cancelled]);
    }
}
