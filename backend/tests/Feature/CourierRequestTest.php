<?php

namespace Tests\Feature;

use App\Enums\OrderChannel;
use App\Models\Order;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\BuildsOrders;
use Tests\TestCase;

class CourierRequestTest extends TestCase
{
    use BuildsOrders, RefreshDatabase;

    private function payload(array $extra = []): array
    {
        return [
            'client_uuid' => (string) Str::uuid(),
            'recipient_phone' => '+228 90 11 22 33',
            'delivery_lat' => 6.1725,
            'delivery_lng' => 1.2314,
            ...$extra,
        ];
    }

    public function test_a_courier_request_follows_the_order_flow(): void
    {
        $operator = $this->operator();
        $restaurant = $this->restaurant();

        $this->actingAs($restaurant)->postJson('/api/v1/courier-requests', $this->payload())
            ->assertCreated()
            ->assertJsonPath('status', 'received')
            ->assertJsonPath('channel', 'courier')
            ->assertJsonPath('delivery.recipient_phone', '+22890112233');

        $order = Order::first();
        $this->assertSame('Course vers +22890112233', $order->request_text);
        $this->assertSame(1, $operator->notifications()->count());
    }

    public function test_the_same_identifier_does_not_create_a_second_request(): void
    {
        $restaurant = $this->restaurant();
        $payload = $this->payload();

        $this->actingAs($restaurant)->postJson('/api/v1/courier-requests', $payload)->assertCreated();
        $this->actingAs($restaurant)->postJson('/api/v1/courier-requests', $payload)->assertOk();

        $this->assertSame(1, Order::count());
    }

    public function test_the_recipient_location_and_a_valid_number_are_required(): void
    {
        $restaurant = $this->restaurant();

        $this->actingAs($restaurant)->postJson('/api/v1/courier-requests', $this->payload(['recipient_phone' => '90']))
            ->assertUnprocessable()->assertJsonValidationErrors('recipient_phone');

        $this->actingAs($restaurant)->postJson('/api/v1/courier-requests', $this->payload(['delivery_lat' => null]))
            ->assertUnprocessable()->assertJsonValidationErrors('delivery_lat');
    }

    public function test_orders_can_be_listed_by_kind(): void
    {
        $restaurant = $this->restaurant();
        $this->newOrder($restaurant);
        $this->actingAs($restaurant)->postJson('/api/v1/courier-requests', $this->payload());

        $this->getJson('/api/v1/orders?kind=courier')->assertJsonCount(1, 'data')->assertJsonPath('data.0.channel', 'courier');
        $this->getJson('/api/v1/orders?kind=goods')->assertJsonCount(1, 'data')->assertJsonPath('data.0.channel', 'text');
        $this->getJson('/api/v1/orders')->assertJsonCount(2, 'data');
    }

    public function test_reordering_a_course_keeps_the_recipient(): void
    {
        $restaurant = $this->restaurant();
        $this->actingAs($restaurant)->postJson('/api/v1/courier-requests', $this->payload());

        $this->postJson('/api/v1/orders/'.Order::first()->id.'/reorder')
            ->assertCreated()
            ->assertJsonPath('channel', 'courier')
            ->assertJsonPath('delivery.recipient_phone', '+22890112233');

        $this->assertSame(OrderChannel::Courier, Order::latest('id')->first()->channel);
    }

    public function test_a_courier_cannot_request_a_course(): void
    {
        $this->actingAs($this->courier())->postJson('/api/v1/courier-requests', $this->payload())->assertForbidden();
    }
}
