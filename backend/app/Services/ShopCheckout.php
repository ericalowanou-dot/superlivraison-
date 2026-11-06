<?php

namespace App\Services;

use App\Enums\OrderChannel;
use App\Exceptions\WorkflowException;
use App\Models\Order;
use App\Models\Product;
use App\Models\Shop;
use App\Models\User;
use App\Notifications\AppEvent;
use Illuminate\Support\Facades\DB;

/** Transforme un panier en commande : les prix viennent de la base, jamais de l'application. */
class ShopCheckout
{
    public function __construct(private OrderWorkflow $workflow) {}

    /** @param array<string, mixed> $data */
    public function place(User $buyer, Shop $shop, array $data): Order
    {
        if (! $shop->isOpen()) {
            throw new WorkflowException('Cette boutique n\'est pas ouverte.');
        }
        if ($shop->owner_id === $buyer->id) {
            throw new WorkflowException('Vous ne pouvez pas acheter dans votre propre boutique.');
        }

        // Le même panier renvoyé après une coupure ne retire pas le stock deux fois.
        $existing = Order::where('restaurant_id', $buyer->id)->where('client_uuid', $data['client_uuid'])->first();
        if ($existing) {
            return $existing;
        }

        $order = DB::transaction(function () use ($buyer, $shop, $data) {
            $quantities = collect($data['items'])
                ->groupBy('product_id')
                ->map(fn ($lines) => $lines->sum('quantity'));

            $products = $shop->products()->where('is_active', true)->whereIn('id', $quantities->keys())->get()->keyBy('id');

            if ($products->count() !== $quantities->count()) {
                throw new WorkflowException('Un article n\'est plus disponible. Vérifiez votre panier.');
            }

            $lines = $products->map(function (Product $product) use ($quantities) {
                $quantity = $quantities[$product->id];
                $this->takeFromStock($product, $quantity);

                return [
                    'product_id' => $product->id,
                    'name' => $product->name,
                    'unit_price' => $product->price,
                    'quantity' => $quantity,
                ];
            })->values();

            $order = $this->workflow->create($buyer, [
                'client_uuid' => $data['client_uuid'],
                'channel' => OrderChannel::Shop,
                'shop_id' => $shop->id,
                'goods_total' => $lines->sum(fn ($line) => $line['unit_price'] * $line['quantity']),
                'request_text' => $lines->map(fn ($line) => "{$line['quantity']} × {$line['name']}")->join(', '),
                'delivery_lat' => $data['delivery_lat'],
                'delivery_lng' => $data['delivery_lng'],
                'delivery_landmark' => $data['delivery_landmark'],
            ]);

            $order->items()->createMany($lines);

            return $order;
        });

        $shop->owner?->notify(new AppEvent('Nouvelle commande', "{$order->reference} : {$order->request_text}"));

        return $order;
    }

    /** Remet les articles en vente quand une commande est annulée. */
    public function restock(Order $order): void
    {
        foreach ($order->items as $item) {
            Product::whereKey($item->product_id)->whereNotNull('stock')->increment('stock', $item->quantity);
        }
    }

    private function takeFromStock(Product $product, int $quantity): void
    {
        if ($product->stock === null) {
            return;
        }

        $taken = Product::whereKey($product->id)->where('stock', '>=', $quantity)->decrement('stock', $quantity);

        if ($taken === 0) {
            throw new WorkflowException("Stock insuffisant pour « {$product->name} ».");
        }
    }
}
