<?php

namespace App\Services;

use App\Enums\OrderChannel;
use App\Enums\OrderStatus;
use App\Enums\PaymentMode;
use App\Enums\Role;
use App\Exceptions\WorkflowException;
use App\Models\Order;
use App\Models\User;
use App\Notifications\AppEvent;
use Closure;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Notification;

/** Toutes les étapes d'une commande passent ici, pour garder les règles et l'historique au même endroit. */
class OrderWorkflow
{
    public function __construct(private PaymentService $payments, private ShopPayouts $payouts) {}

    /** @param array<string, mixed> $data */
    public function create(User $restaurant, array $data): Order
    {
        if ($restaurant->city_id === null) {
            throw new WorkflowException('Choisissez votre ville avant de commander.');
        }

        $order = Order::createOrFirst(
            ['restaurant_id' => $restaurant->id, 'client_uuid' => $data['client_uuid']],
            [...$data, 'city_id' => $restaurant->city_id],
        );

        if ($order->wasRecentlyCreated) {
            $order->events()->create(['actor_id' => $restaurant->id, 'to_status' => OrderStatus::Received]);

            Notification::send(
                User::whereIn('role', [Role::Operator, Role::Admin])->where('is_active', true)->get(),
                new AppEvent('Nouvelle demande', "{$order->reference} attend un prix.", $order),
            );
        }

        return $order;
    }

    public function setPrice(Order $order, int $price, User $operator): Order
    {
        if ($price <= 0) {
            throw new WorkflowException('Le prix doit être supérieur à zéro.');
        }

        $order = $this->move($order, OrderStatus::PricePending, $operator, "Prix : {$price} FCFA", function (Order $o) use ($price) {
            // Pour un achat en boutique, l'opérateur ne fixe que les frais de livraison.
            if ($o->channel === OrderChannel::Shop) {
                $o->delivery_fee = $price;
                $o->price = $o->goods_total + $price;
            } else {
                $o->price = $price;
            }
            $o->priced_at = now();
            $o->refusal_reason = null;
        });

        $this->notifyRestaurant($order, 'Prix à valider', "Le prix de {$order->reference} est de {$order->price} FCFA.");

        return $order;
    }

    /** $price est le prix affiché au restaurant : s'il a changé entre-temps, il doit le revoir. */
    public function acceptPrice(Order $order, User $restaurant, PaymentMode $mode, int $price): Order
    {
        $order = $this->move($order, OrderStatus::Confirmed, $restaurant, $mode->getLabel(), function (Order $o) use ($mode, $price) {
            if ($o->price !== $price) {
                throw new WorkflowException('Le prix a changé. Vérifiez le nouveau montant.');
            }
            $o->payment_mode = $mode;
            $o->confirmed_at = now();
        });

        if ($mode === PaymentMode::Cash) {
            $this->payments->registerCash($order);
        }

        return $order;
    }

    public function refusePrice(Order $order, User $restaurant, ?string $reason): Order
    {
        return $this->move($order, OrderStatus::Received, $restaurant, $reason, function (Order $o) use ($reason) {
            $o->price = null;
            $o->delivery_fee = null;
            $o->priced_at = null;
            $o->refusal_reason = $reason;
        });
    }

    public function startPreparing(Order $order, User $actor): Order
    {
        $order = $this->move($order, OrderStatus::Preparing, $actor, null, function (Order $o) {
            if ($o->payment_mode === PaymentMode::MobileMoney && ! $o->isPaid()) {
                throw new WorkflowException('Le paiement mobile doit être reçu avant la préparation.');
            }
        });

        $order->shop?->owner?->notify(new AppEvent('Commande à préparer', "{$order->reference} : {$order->request_text}"));

        return $order;
    }

    public function assignCourier(Order $order, User $courier, User $actor): Order
    {
        if ($courier->role !== Role::Courier || ! $courier->is_active) {
            throw new WorkflowException('Cette personne n\'est pas un livreur actif.');
        }

        $order = DB::transaction(function () use ($order, $courier, $actor) {
            $locked = Order::lockForUpdate()->findOrFail($order->id);

            if (! in_array($locked->status, [OrderStatus::Confirmed, OrderStatus::Preparing], true)) {
                throw new WorkflowException('Le livreur s\'affecte sur une commande confirmée ou en préparation.');
            }

            $locked->courier_id = $courier->id;
            $locked->save();
            $locked->events()->create([
                'actor_id' => $actor->id,
                'from_status' => $locked->status,
                'to_status' => $locked->status,
                'note' => 'Livreur : '.($courier->name ?? $courier->phone),
            ]);

            return $locked;
        });

        $courier->notify(new AppEvent('Livraison affectée', "{$order->reference} vous est affectée.", $order));

        return $order;
    }

    public function startDelivery(Order $order, User $actor): Order
    {
        $order = $this->move($order, OrderStatus::Delivering, $actor, null, function (Order $o) {
            if ($o->courier_id === null) {
                throw new WorkflowException('Affectez un livreur avant le départ.');
            }
        });

        $this->notifyRestaurant($order, 'Commande en livraison', "{$order->reference} est en route.");

        return $order;
    }

    public function markDelivered(Order $order, User $actor): Order
    {
        $order = $this->move($order, OrderStatus::Delivered, $actor, null, function (Order $o) {
            $o->delivered_at = now();
        });

        // À la livraison, le livreur qui remet la commande confirme aussi l'encaissement.
        if ($order->payment_mode === PaymentMode::Cash) {
            $this->payments->confirmCash($order);
            $order->refresh();
        }

        $this->payouts->record($order);

        $this->notifyRestaurant($order, 'Commande livrée', "{$order->reference} a été livrée.");

        return $order;
    }

    public function cancel(Order $order, User $actor, string $reason): Order
    {
        $order = $this->move($order, OrderStatus::Cancelled, $actor, $reason, function (Order $o) use ($actor, $reason) {
            $byRestaurant = $actor->role === Role::Restaurant;

            if ($byRestaurant && ! in_array($o->status, [OrderStatus::Received, OrderStatus::PricePending], true)) {
                throw new WorkflowException('Cette commande ne peut plus être annulée depuis l\'application.');
            }
            $o->cancel_reason = $reason;
        });

        $this->payments->closePending($order);

        if ($order->channel === OrderChannel::Shop) {
            app(ShopCheckout::class)->restock($order);
            $order->shop?->owner?->notify(new AppEvent('Commande annulée', "{$order->reference} : {$reason}"));
        }

        if ($actor->id !== $order->restaurant_id) {
            $this->notifyRestaurant($order, 'Commande annulée', "{$order->reference} : {$reason}");
        }

        return $order;
    }

    /** Change le statut sous verrou : deux actions simultanées ne peuvent pas se croiser. */
    private function move(Order $order, OrderStatus $to, User $actor, ?string $note, ?Closure $apply = null): Order
    {
        return DB::transaction(function () use ($order, $to, $actor, $note, $apply) {
            $locked = Order::lockForUpdate()->findOrFail($order->id);
            $from = $locked->status;

            if (! $from->canMoveTo($to)) {
                throw new WorkflowException("Action impossible : la commande est « {$from->getLabel()} ».");
            }

            if ($apply) {
                $apply($locked);
            }

            $locked->status = $to;
            $locked->save();
            $locked->events()->create([
                'actor_id' => $actor->id,
                'from_status' => $from,
                'to_status' => $to,
                'note' => $note,
            ]);

            return $locked;
        });
    }

    private function notifyRestaurant(Order $order, string $title, string $body): void
    {
        $order->restaurant->notify(new AppEvent($title, $body, $order));
    }
}
