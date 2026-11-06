<?php

namespace Tests\Feature;

use App\Enums\OrderStatus;
use App\Enums\PaymentMode;
use App\Enums\PayoutStatus;
use App\Enums\ReviewStatus;
use App\Enums\Role;
use App\Filament\Resources\Orders\Pages\ViewOrder;
use App\Filament\Resources\Payouts\Pages\ListPayouts;
use App\Filament\Resources\Products\Pages\ListProducts;
use App\Models\Order;
use App\Models\Payout;
use App\Models\Product;
use App\Models\Shop;
use App\Models\User;
use App\Services\ShopModeration;
use App\Services\ShopPayouts;
use Filament\Actions\Testing\TestAction;
use Filament\Facades\Filament;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\Concerns\BuildsOrders;
use Tests\TestCase;

class MarketplaceTest extends TestCase
{
    use BuildsOrders, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake(config('superlivraison.media_disk'));
    }

    private function createShop(User $seller): Shop
    {
        $this->actingAs($seller)->post('/api/v1/my-shop', [
            'name' => 'Boutique Afia',
            'phone' => '+228 90 00 00 01',
            'landmark' => 'Marché de Bè',
        ], ['Accept' => 'application/json'])->assertCreated()->assertJsonPath('status', 'pending');

        return Shop::where('owner_id', $seller->id)->firstOrFail();
    }

    private function openShop(?User $seller = null): Shop
    {
        $shop = $this->createShop($seller ?? $this->restaurant());
        app(ShopModeration::class)->approve($shop);

        return $shop->refresh();
    }

    private function product(Shop $shop, array $extra = []): Product
    {
        return $shop->products()->create(['name' => 'Riz 5 kg', 'price' => 4000, 'image_path' => 'products/riz.jpg', ...$extra]);
    }

    private function checkout(User $buyer, Shop $shop, array $items, array $extra = [])
    {
        return $this->actingAs($buyer)->postJson("/api/v1/shops/{$shop->id}/orders", [
            'client_uuid' => (string) Str::uuid(),
            'items' => $items,
            'delivery_lat' => 6.17,
            'delivery_lng' => 1.23,
            'delivery_landmark' => 'Face à la pharmacie',
            ...$extra,
        ]);
    }

    public function test_a_new_shop_stays_hidden_until_it_is_approved(): void
    {
        $operator = $this->operator();
        $seller = $this->restaurant();
        $buyer = $this->restaurant();
        $shop = $this->createShop($seller);
        $this->product($shop);

        $this->assertSame(1, $operator->notifications()->count());
        $this->actingAs($buyer)->getJson('/api/v1/shops')->assertJsonCount(0, 'data');
        $this->getJson("/api/v1/shops/{$shop->id}/products")->assertNotFound();

        app(ShopModeration::class)->approve($shop);

        $this->getJson('/api/v1/shops')->assertJsonCount(1, 'data');
        $this->getJson("/api/v1/shops/{$shop->id}/products")->assertJsonCount(1, 'data');
    }

    public function test_a_rejected_shop_goes_back_to_validation_once_corrected(): void
    {
        $operator = $this->operator();
        $seller = $this->restaurant();
        $shop = $this->createShop($seller);
        app(ShopModeration::class)->reject($shop, 'Nom incomplet');

        $this->actingAs($seller)->getJson('/api/v1/my-shop')->assertJsonPath('shop.rejection_reason', 'Nom incomplet');

        $this->post('/api/v1/my-shop', ['name' => 'Boutique Afia Bè', 'phone' => '+22890000001', 'landmark' => 'Bè'], ['Accept' => 'application/json'])
            ->assertOk()->assertJsonPath('status', 'pending');

        $this->assertSame(ReviewStatus::Pending, $shop->refresh()->status);
        $this->assertSame(2, $operator->notifications()->count());
    }

    public function test_a_seller_manages_their_products(): void
    {
        $seller = $this->restaurant();
        $this->createShop($seller);

        $this->post('/api/v1/my-shop/products', [
            'name' => 'Huile 1 L',
            'price' => 1500,
            'stock' => 8,
            'image' => UploadedFile::fake()->image('huile.jpg'),
        ], ['Accept' => 'application/json'])->assertCreated()->assertJsonPath('stock', 8);

        $product = Product::firstOrFail();

        $this->post("/api/v1/my-shop/products/{$product->id}", ['name' => 'Huile 2 L', 'price' => 2800, 'is_active' => '0'], ['Accept' => 'application/json'])
            ->assertOk()->assertJsonPath('name', 'Huile 2 L')->assertJsonPath('is_active', false);

        $this->getJson('/api/v1/my-shop/products')->assertJsonCount(1, 'data');
        $this->actingAs($this->restaurant())->deleteJson("/api/v1/my-shop/products/{$product->id}")->assertNotFound();

        $this->actingAs($seller)->deleteJson("/api/v1/my-shop/products/{$product->id}")->assertNoContent();
        $this->assertSame(0, Product::count());
    }

    public function test_a_product_cannot_be_sold_without_a_photo(): void
    {
        $seller = $this->restaurant();
        $this->createShop($seller);

        $this->postJson('/api/v1/my-shop/products', ['name' => 'Huile', 'price' => 1500])
            ->assertUnprocessable()->assertJsonValidationErrors('image');
    }

    public function test_the_whole_purchase_ends_with_a_payout_for_the_seller(): void
    {
        config(['superlivraison.shop_commission_percent' => 10]);

        $seller = $this->restaurant();
        $buyer = $this->restaurant();
        $shop = $this->openShop($seller);
        $rice = $this->product($shop, ['stock' => 5]);
        $oil = $this->product($shop, ['name' => 'Huile', 'price' => 1000]);

        $this->checkout($buyer, $shop, [
            ['product_id' => $rice->id, 'quantity' => 2],
            ['product_id' => $oil->id, 'quantity' => 1],
        ])
            ->assertCreated()
            ->assertJsonPath('channel', 'shop')
            ->assertJsonPath('goods_total', 9000)
            ->assertJsonPath('shop.name', 'Boutique Afia')
            ->assertJsonCount(2, 'items');

        $order = Order::firstOrFail();
        $this->assertSame(3, $rice->refresh()->stock);
        $this->assertNull($oil->refresh()->stock);
        $this->assertSame(2, $seller->notifications()->count());

        $order = $this->workflow()->setPrice($order, 1500, $this->operator());
        $this->assertSame(1500, $order->delivery_fee);
        $this->assertSame(10500, $order->price);

        $order = $this->workflow()->acceptPrice($order, $buyer, PaymentMode::Cash, 10500);
        $order = $this->workflow()->startPreparing($order, $this->operator());
        $order = $this->workflow()->assignCourier($order, $this->courier(), $this->operator());
        $order = $this->workflow()->startDelivery($order, $this->operator());
        $this->workflow()->markDelivered($order, $this->operator());

        $payout = Payout::firstOrFail();
        $this->assertSame(9000, $payout->goods_total);
        $this->assertSame(900, $payout->commission);
        $this->assertSame(8100, $payout->amount);
        $this->assertSame(PayoutStatus::Pending, $payout->status);

        $this->actingAs($seller)->getJson('/api/v1/my-shop/payouts')
            ->assertJsonPath('to_receive', 8100)
            ->assertJsonPath('data.0.order_reference', $order->reference);

        app(ShopPayouts::class)->markPaid($payout, 'TX-1');
        $this->getJson('/api/v1/my-shop/payouts')->assertJsonPath('to_receive', 0);
    }

    public function test_the_price_comes_from_the_server(): void
    {
        $shop = $this->openShop();
        $rice = $this->product($shop);

        $this->checkout($this->restaurant(), $shop, [['product_id' => $rice->id, 'quantity' => 1, 'unit_price' => 1]])
            ->assertCreated()->assertJsonPath('goods_total', 4000);
    }

    public function test_the_same_cart_sent_twice_takes_the_stock_once(): void
    {
        $shop = $this->openShop();
        $rice = $this->product($shop, ['stock' => 5]);
        $buyer = $this->restaurant();
        $uuid = (string) Str::uuid();

        $this->checkout($buyer, $shop, [['product_id' => $rice->id, 'quantity' => 2]], ['client_uuid' => $uuid])->assertCreated();
        $this->checkout($buyer, $shop, [['product_id' => $rice->id, 'quantity' => 2]], ['client_uuid' => $uuid])->assertOk();

        $this->assertSame(3, $rice->refresh()->stock);
        $this->assertSame(1, Order::count());
    }

    public function test_an_empty_stock_refuses_the_order_and_changes_nothing(): void
    {
        $shop = $this->openShop();
        $rice = $this->product($shop, ['stock' => 5]);
        $oil = $this->product($shop, ['name' => 'Huile', 'stock' => 1]);

        $this->checkout($this->restaurant(), $shop, [
            ['product_id' => $rice->id, 'quantity' => 2],
            ['product_id' => $oil->id, 'quantity' => 2],
        ])->assertStatus(409);

        $this->assertSame(5, $rice->refresh()->stock);
        $this->assertSame(0, Order::count());
    }

    public function test_a_cart_cannot_mix_two_shops(): void
    {
        $shop = $this->openShop();
        $other = $this->openShop();
        $foreign = $this->product($other);

        $this->checkout($this->restaurant(), $shop, [['product_id' => $foreign->id, 'quantity' => 1]])->assertStatus(409);
    }

    public function test_a_seller_cannot_buy_from_their_own_shop(): void
    {
        $seller = $this->restaurant();
        $shop = $this->openShop($seller);
        $rice = $this->product($shop);

        $this->checkout($seller, $shop, [['product_id' => $rice->id, 'quantity' => 1]])->assertStatus(409);
    }

    public function test_cancelling_puts_the_articles_back_on_sale(): void
    {
        $shop = $this->openShop();
        $rice = $this->product($shop, ['stock' => 5]);
        $buyer = $this->restaurant();

        $this->checkout($buyer, $shop, [['product_id' => $rice->id, 'quantity' => 2]])->assertCreated();
        $this->postJson('/api/v1/orders/'.Order::first()->id.'/cancel', ['reason' => 'Erreur'])->assertOk();

        $this->assertSame(5, $rice->refresh()->stock);
    }

    public function test_a_seller_sees_the_articles_but_not_the_buyer_address(): void
    {
        $seller = $this->restaurant();
        $shop = $this->openShop($seller);
        $rice = $this->product($shop);
        $this->checkout($this->restaurant(), $shop, [['product_id' => $rice->id, 'quantity' => 1]]);

        $response = $this->actingAs($seller)->getJson('/api/v1/my-shop/orders')
            ->assertJsonPath('data.0.items.0.name', 'Riz 5 kg');

        $this->assertArrayNotHasKey('delivery', $response->json('data.0'));
        $this->assertStringNotContainsString('pharmacie', $response->getContent());
    }

    public function test_the_courier_sees_where_to_pick_up(): void
    {
        $shop = $this->openShop();
        $rice = $this->product($shop);
        $buyer = $this->restaurant();
        $courier = $this->courier();
        $this->checkout($buyer, $shop, [['product_id' => $rice->id, 'quantity' => 1]]);

        $order = $this->workflow()->setPrice(Order::firstOrFail(), 1000, $this->operator());
        $order = $this->workflow()->acceptPrice($order, $buyer, PaymentMode::Cash, 5000);
        $this->workflow()->assignCourier($order, $courier, $this->operator());

        $this->actingAs($courier)->getJson('/api/v1/courier/deliveries')
            ->assertJsonPath('0.shop.landmark', 'Marché de Bè')
            ->assertJsonPath('0.items.0.quantity', 1);
    }

    public function test_a_shop_order_cannot_be_reordered_blindly(): void
    {
        $shop = $this->openShop();
        $rice = $this->product($shop);
        $buyer = $this->restaurant();
        $this->checkout($buyer, $shop, [['product_id' => $rice->id, 'quantity' => 1]]);

        $this->postJson('/api/v1/orders/'.Order::first()->id.'/reorder')->assertStatus(409);
    }

    public function test_a_refund_cancels_a_payout_not_yet_sent(): void
    {
        $shop = $this->openShop();
        $rice = $this->product($shop);
        $this->checkout($this->restaurant(), $shop, [['product_id' => $rice->id, 'quantity' => 1]]);
        $order = Order::firstOrFail();
        $order->forceFill(['status' => OrderStatus::Delivered])->save();

        $payouts = app(ShopPayouts::class);
        $payout = $payouts->record($order);
        $payouts->cancelFor($order);

        $this->assertSame(PayoutStatus::Cancelled, $payout->refresh()->status);
    }

    public function test_the_team_fixes_the_fee_and_handles_payouts_from_the_administration(): void
    {
        Filament::setCurrentPanel(Filament::getPanel('admin'));
        $admin = User::factory()->role(Role::Admin)->create(['email' => fake()->unique()->safeEmail()]);
        $shop = $this->openShop();
        $rice = $this->product($shop);
        $this->checkout($this->restaurant(), $shop, [['product_id' => $rice->id, 'quantity' => 1]]);
        $order = Order::firstOrFail();

        $this->actingAs($admin, 'web');

        Livewire::test(ViewOrder::class, ['record' => $order->getRouteKey()])
            ->callAction('setPrice', ['price' => 1000]);
        $this->assertSame(5000, $order->refresh()->price);

        Livewire::test(ListProducts::class)->assertCanSeeTableRecords([$rice]);

        $payout = app(ShopPayouts::class)->record($order);

        Livewire::test(ListPayouts::class)
            ->assertCanSeeTableRecords([$payout])
            ->callAction(TestAction::make('markPaid')->table($payout), ['reference' => 'TX-9']);

        $this->assertSame(PayoutStatus::Paid, $payout->refresh()->status);
    }
}
