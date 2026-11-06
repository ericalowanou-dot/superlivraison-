<?php

namespace Tests\Feature;

use App\Enums\OrderChannel;
use App\Enums\OrderStatus;
use App\Enums\PaymentMode;
use App\Enums\PaymentStatus;
use App\Exceptions\WorkflowException;
use App\Models\Order;
use App\Models\User;
use App\Models\VoiceNote;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Tests\Concerns\BuildsOrders;
use Tests\TestCase;

class OrderFlowTest extends TestCase
{
    use BuildsOrders, RefreshDatabase;

    private function payload(array $extra = []): array
    {
        return [
            'client_uuid' => (string) Str::uuid(),
            'request_text' => '20 kg de riz et 10 L d\'huile',
            'delivery_lat' => 6.1725,
            'delivery_lng' => 1.2314,
            'delivery_landmark' => 'Face à la pharmacie',
            ...$extra,
        ];
    }

    public function test_a_restaurant_places_a_text_order(): void
    {
        $operator = $this->operator();
        $restaurant = $this->restaurant();

        $this->actingAs($restaurant)->postJson('/api/v1/orders', $this->payload())
            ->assertCreated()
            ->assertJsonPath('status', 'received')
            ->assertJsonPath('channel', 'text');

        $order = Order::first();
        $this->assertSame('CMD-'.(1000 + $order->id), $order->reference);
        $this->assertSame(1, $operator->notifications()->count());
    }

    public function test_resending_after_a_network_cut_does_not_duplicate_the_order(): void
    {
        $restaurant = $this->restaurant();
        $payload = $this->payload();

        $this->actingAs($restaurant)->postJson('/api/v1/orders', $payload)->assertCreated();
        $this->actingAs($restaurant)->postJson('/api/v1/orders', $payload)->assertOk();

        $this->assertSame(1, Order::count());
    }

    public function test_a_city_is_required_before_ordering(): void
    {
        $this->actingAs(User::factory()->create())->postJson('/api/v1/orders', $this->payload())->assertStatus(409);
    }

    public function test_a_voice_order_keeps_the_audio_for_the_operator(): void
    {
        Storage::fake('local');
        $restaurant = $this->restaurant();

        $note = $this->actingAs($restaurant)->post('/api/v1/voice-notes', [
            'audio' => UploadedFile::fake()->create('vocal.m4a', 200, 'audio/mp4'),
            'duration_seconds' => 12,
        ], ['Accept' => 'application/json'])->assertCreated()->assertJsonPath('status', 'done')->json();

        $this->assertNotEmpty($note['transcript']);

        $this->postJson('/api/v1/orders', $this->payload([
            'request_text' => 'Texte corrigé par le restaurant',
            'voice_note_id' => $note['id'],
        ]))->assertCreated()->assertJsonPath('channel', 'voice')->assertJsonPath('has_voice', true);

        $order = Order::first();
        $this->assertSame(OrderChannel::Voice, $order->channel);
        $this->assertSame('Texte corrigé par le restaurant', $order->request_text);
        $this->actingAs($this->operator())->get("/api/v1/orders/{$order->id}/voice")->assertOk();
    }

    public function test_an_other_users_voice_note_cannot_be_attached_or_read(): void
    {
        $note = VoiceNote::create(['user_id' => $this->restaurant()->id, 'path' => 'x.m4a', 'status' => 'done']);
        $other = $this->restaurant();

        $this->actingAs($other)->postJson('/api/v1/orders', $this->payload(['voice_note_id' => $note->id]))->assertStatus(422);
        $this->getJson("/api/v1/voice-notes/{$note->id}")->assertNotFound();
    }

    public function test_a_non_audio_file_is_refused(): void
    {
        Storage::fake('local');

        $this->actingAs($this->restaurant())->post('/api/v1/voice-notes', [
            'audio' => UploadedFile::fake()->create('virus.php', 10, 'application/x-php'),
        ], ['Accept' => 'application/json'])->assertStatus(422);
    }

    public function test_full_order_paid_in_cash(): void
    {
        $order = $this->newOrder();
        $restaurant = $order->restaurant;
        $operator = $this->operator();
        $courier = $this->courier();

        $order = $this->workflow()->setPrice($order, 12000, $operator);

        $this->actingAs($restaurant)->postJson("/api/v1/orders/{$order->id}/accept-price", ['payment_mode' => 'cash', 'price' => 12000])
            ->assertOk()->assertJsonPath('status', 'confirmed');

        $order = $this->workflow()->startPreparing($order, $operator);
        $order = $this->workflow()->assignCourier($order, $courier, $operator);

        $this->actingAs($courier)->getJson('/api/v1/courier/deliveries')->assertOk()->assertJsonCount(1);
        $this->postJson("/api/v1/courier/deliveries/{$order->id}/start")->assertOk()->assertJsonPath('status', 'delivering');
        $this->postJson("/api/v1/courier/deliveries/{$order->id}/delivered")->assertOk()->assertJsonPath('status', 'delivered')->assertJsonPath('is_paid', true);

        $this->assertSame(PaymentStatus::Succeeded, $order->payments()->first()->status);
        $this->assertSame(['delivered', 'delivering', 'preparing', 'preparing', 'confirmed', 'price_pending', 'received'],
            $order->events()->get()->map(fn ($e) => $e->to_status->value)->all());
    }

    public function test_a_refused_price_returns_to_the_operator(): void
    {
        $order = $this->workflow()->setPrice($this->newOrder(), 9000, $this->operator());

        $this->actingAs($order->restaurant)->postJson("/api/v1/orders/{$order->id}/refuse-price", ['reason' => 'Trop cher'])
            ->assertOk()->assertJsonPath('status', 'received')->assertJsonPath('price', null);
    }

    public function test_accepting_a_price_that_changed_is_refused(): void
    {
        $operator = $this->operator();
        $order = $this->workflow()->setPrice($this->newOrder(), 9000, $operator);
        $this->workflow()->setPrice($order, 15000, $operator);

        $this->actingAs($order->restaurant)->postJson("/api/v1/orders/{$order->id}/accept-price", ['payment_mode' => 'cash', 'price' => 9000])
            ->assertStatus(409);
        $this->assertSame(OrderStatus::PricePending, $order->fresh()->status);
    }

    public function test_a_restaurant_cannot_skip_a_step(): void
    {
        $order = $this->newOrder();

        $this->actingAs($order->restaurant)->postJson("/api/v1/orders/{$order->id}/accept-price", ['payment_mode' => 'cash', 'price' => 1])
            ->assertStatus(409);
    }

    public function test_a_mobile_order_cannot_be_prepared_before_payment(): void
    {
        $this->expectException(WorkflowException::class);

        $this->workflow()->startPreparing($this->confirmedOrder(PaymentMode::MobileMoney), $this->operator());
    }

    public function test_delivery_needs_a_courier(): void
    {
        $operator = $this->operator();
        $order = $this->workflow()->startPreparing($this->confirmedOrder(PaymentMode::Cash), $operator);

        $this->expectException(WorkflowException::class);
        $this->workflow()->startDelivery($order, $operator);
    }

    public function test_a_restaurant_cannot_be_assigned_as_courier(): void
    {
        $this->expectException(WorkflowException::class);

        $this->workflow()->assignCourier($this->confirmedOrder(PaymentMode::Cash), $this->restaurant(), $this->operator());
    }

    public function test_a_restaurant_cannot_cancel_once_confirmed(): void
    {
        $order = $this->confirmedOrder(PaymentMode::Cash);

        $this->actingAs($order->restaurant)->postJson("/api/v1/orders/{$order->id}/cancel", ['reason' => 'Erreur'])->assertStatus(409);
        $this->assertSame(OrderStatus::Confirmed, $order->fresh()->status);
    }

    public function test_cancelling_a_cash_order_closes_its_payment(): void
    {
        $order = $this->confirmedOrder(PaymentMode::Cash);

        $this->workflow()->cancel($order, $this->operator(), 'Rupture');

        $this->assertSame(PaymentStatus::Failed, $order->payments()->first()->status);
    }

    public function test_a_delivered_order_cannot_change(): void
    {
        $operator = $this->operator();
        $order = $this->workflow()->assignCourier($this->confirmedOrder(PaymentMode::Cash), $this->courier(), $operator);
        $order = $this->workflow()->startPreparing($order, $operator);
        $order = $this->workflow()->startDelivery($order, $operator);
        $order = $this->workflow()->markDelivered($order, $operator);

        $this->expectException(WorkflowException::class);
        $this->workflow()->cancel($order, $operator, 'Trop tard');
    }

    public function test_orders_are_private(): void
    {
        $order = $this->newOrder();
        $stranger = $this->restaurant();

        $this->actingAs($stranger)->getJson("/api/v1/orders/{$order->id}")->assertForbidden();
        $this->postJson("/api/v1/orders/{$order->id}/cancel", ['reason' => 'x'])->assertForbidden();
        $this->postJson("/api/v1/orders/{$order->id}/reorder")->assertForbidden();
        $this->getJson('/api/v1/orders')->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_a_courier_only_handles_their_own_deliveries(): void
    {
        $operator = $this->operator();
        $order = $this->workflow()->assignCourier($this->confirmedOrder(PaymentMode::Cash), $this->courier(), $operator);

        $this->actingAs($this->courier())->postJson("/api/v1/courier/deliveries/{$order->id}/start")->assertForbidden();
        $this->actingAs($order->restaurant)->postJson("/api/v1/courier/deliveries/{$order->id}/delivered")->assertForbidden();
    }

    public function test_reorder_creates_a_new_request(): void
    {
        $order = $this->newOrder();

        $this->actingAs($order->restaurant)->postJson("/api/v1/orders/{$order->id}/reorder")
            ->assertCreated()->assertJsonPath('request_text', '20 kg de riz')->assertJsonPath('status', 'received');
    }

    public function test_account_deletion_removes_personal_data_and_keeps_orders(): void
    {
        $operator = $this->operator();
        $order = $this->workflow()->cancel($this->newOrder(), $operator, 'Test');
        $user = $order->restaurant;
        $user->createToken('t');

        $this->actingAs($user)->deleteJson('/api/v1/me')->assertNoContent();

        $deleted = User::withTrashed()->find($user->id);
        $this->assertNull($deleted->phone);
        $this->assertNull($deleted->name);
        $this->assertSame(0, $deleted->tokens()->count());
        $this->assertNotNull(Order::find($order->id));
    }

    public function test_account_deletion_is_refused_with_an_open_order(): void
    {
        $order = $this->newOrder();

        $this->actingAs($order->restaurant)->deleteJson('/api/v1/me')->assertStatus(409);
    }

    public function test_reference_data_is_public(): void
    {
        $this->city();

        $this->getJson('/api/v1/reference')->assertOk()->assertJsonPath('countries.0.cities.0.name', 'Lomé');
    }
}
