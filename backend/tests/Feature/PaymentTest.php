<?php

namespace Tests\Feature;

use App\Contracts\PaymentGateway;
use App\Enums\OrderStatus;
use App\Enums\PaymentMode;
use App\Enums\PaymentStatus;
use App\Enums\Role;
use App\Exceptions\WorkflowException;
use App\Models\Order;
use App\Models\Payment;
use App\Models\User;
use App\Services\PaymentService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use RuntimeException;
use Tests\Concerns\BuildsOrders;
use Tests\TestCase;

class PaymentTest extends TestCase
{
    use BuildsOrders, RefreshDatabase;

    private function start(Order $order): Payment
    {
        $id = $this->actingAs($order->restaurant)
            ->postJson("/api/v1/orders/{$order->id}/payments", ['method' => 'flooz', 'phone' => '+228 96 00 00 01'])
            ->assertCreated()->assertJsonPath('status', 'pending')->json('id');

        return Payment::find($id);
    }

    private function webhook(Payment $payment, array $over = [], ?string $signature = null): TestResponse
    {
        $body = json_encode(['reference' => $payment->reference, 'status' => 'success', 'amount' => $payment->amount, ...$over]);

        return $this->call('POST', '/api/v1/webhooks/payments/fake', [], [], [], [
            'CONTENT_TYPE' => 'application/json',
            'HTTP_X_SIGNATURE' => $signature ?? hash_hmac('sha256', $body, config('superlivraison.fake_payment_secret')),
        ], $body);
    }

    public function test_a_signed_webhook_confirms_the_payment(): void
    {
        $order = $this->confirmedOrder();
        $payment = $this->start($order);

        $this->assertFalse($order->fresh()->isPaid());

        $this->webhook($payment)->assertOk();

        $this->assertSame(PaymentStatus::Succeeded, $payment->fresh()->status);
        $this->assertTrue($order->fresh()->isPaid());
        $this->assertSame(1, $order->restaurant->notifications()->where('data->title', 'Paiement réussi')->count());
    }

    public function test_paid_orders_can_then_be_prepared(): void
    {
        $order = $this->confirmedOrder();
        $this->webhook($this->start($order));

        $this->assertSame(OrderStatus::Preparing, $this->workflow()->startPreparing($order, $this->operator())->status);
    }

    public function test_a_forged_webhook_is_refused(): void
    {
        $order = $this->confirmedOrder();
        $payment = $this->start($order);

        $this->webhook($payment, signature: 'fausse-signature')->assertUnauthorized();

        $this->assertSame(PaymentStatus::Pending, $payment->fresh()->status);
        $this->assertFalse($order->fresh()->isPaid());
    }

    public function test_a_webhook_for_another_provider_is_refused(): void
    {
        $this->postJson('/api/v1/webhooks/payments/autre', [])->assertNotFound();
    }

    public function test_a_repeated_webhook_changes_nothing(): void
    {
        $order = $this->confirmedOrder();
        $payment = $this->start($order);

        $this->webhook($payment)->assertOk();
        $this->webhook($payment)->assertOk();
        $this->webhook($payment, ['status' => 'failed'])->assertOk();

        $this->assertSame(PaymentStatus::Succeeded, $payment->fresh()->status);
        $this->assertSame(1, $order->restaurant->notifications()->where('data->title', 'Paiement réussi')->count());
    }

    public function test_a_wrong_amount_does_not_pay_the_order(): void
    {
        $order = $this->confirmedOrder(price: 5000);
        $payment = $this->start($order);

        $this->webhook($payment, ['amount' => 100])->assertOk();

        $this->assertSame(PaymentStatus::Pending, $payment->fresh()->status);
        $this->assertTrue($payment->fresh()->needs_review);
        $this->assertFalse($order->fresh()->isPaid());
    }

    public function test_a_failed_payment_can_be_retried(): void
    {
        $order = $this->confirmedOrder();
        $payment = $this->start($order);

        $this->webhook($payment, ['status' => 'failed', 'reason' => 'Solde insuffisant'])->assertOk();

        $this->assertSame(PaymentStatus::Failed, $payment->fresh()->status);
        $this->start($order);
    }

    public function test_two_payments_cannot_run_at_once(): void
    {
        $order = $this->confirmedOrder();
        $this->start($order);

        $this->actingAs($order->restaurant)
            ->postJson("/api/v1/orders/{$order->id}/payments", ['method' => 'mixx', 'phone' => '+22890000002'])
            ->assertStatus(409);
    }

    public function test_a_late_success_after_a_new_payment_is_flagged(): void
    {
        $order = $this->confirmedOrder();
        $first = $this->start($order);
        $this->travel(16)->minutes();
        $second = $this->start($order);

        $this->webhook($second)->assertOk();
        $this->webhook($first)->assertOk();

        $this->assertTrue($first->fresh()->needs_review);
        $this->assertFalse($second->fresh()->needs_review);
    }

    public function test_a_payment_arriving_after_cancellation_is_flagged(): void
    {
        $order = $this->confirmedOrder();
        $payment = $this->start($order);
        $this->workflow()->cancel($order, $this->operator(), 'Rupture');

        $this->webhook($payment)->assertOk();

        $this->assertTrue($payment->fresh()->needs_review);
        $this->assertFalse($order->fresh()->isPaid());
    }

    public function test_the_list_of_orders_to_pay_only_shows_unpaid_mobile_orders(): void
    {
        $due = $this->confirmedOrder();
        $this->newOrder($due->restaurant);

        $this->actingAs($due->restaurant)->getJson('/api/v1/orders?to_pay=1')
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $due->id);
    }

    public function test_a_cash_order_refuses_mobile_payment(): void
    {
        $order = $this->confirmedOrder(PaymentMode::Cash);

        $this->actingAs($order->restaurant)
            ->postJson("/api/v1/orders/{$order->id}/payments", ['method' => 'flooz', 'phone' => '+22890000002'])
            ->assertStatus(409);
    }

    public function test_only_the_owner_can_pay_or_see_a_payment(): void
    {
        $order = $this->confirmedOrder();
        $payment = $this->start($order);
        $stranger = $this->restaurant();

        $this->actingAs($stranger)
            ->postJson("/api/v1/orders/{$order->id}/payments", ['method' => 'flooz', 'phone' => '+22890000002'])
            ->assertForbidden();
        $this->getJson("/api/v1/payments/{$payment->id}")->assertForbidden();
        $this->getJson("/api/v1/payments/{$payment->id}/receipt")->assertForbidden();
    }

    public function test_the_receipt_is_a_pdf_once_paid(): void
    {
        $order = $this->confirmedOrder();
        $payment = $this->start($order);

        $this->getJson("/api/v1/payments/{$payment->id}/receipt")->assertStatus(409);

        $this->webhook($payment);

        $response = $this->actingAs($order->restaurant)->get("/api/v1/payments/{$payment->id}/receipt")->assertOk();
        $this->assertSame('application/pdf', $response->headers->get('Content-Type'));
    }

    public function test_a_payment_is_refunded_only_once(): void
    {
        $order = $this->confirmedOrder();
        $payment = $this->start($order);
        $this->webhook($payment);
        $admin = User::factory()->role(Role::Admin)->create();
        $service = app(PaymentService::class);

        $service->refund($payment, $admin);
        $this->assertSame(PaymentStatus::Refunded, $payment->fresh()->status);

        $this->expectException(WorkflowException::class);
        $service->refund($payment, $admin);
    }

    public function test_simulated_services_are_refused_in_production(): void
    {
        $this->app['env'] = 'production';
        $this->app->forgetInstance(PaymentGateway::class);

        $this->expectException(RuntimeException::class);
        app(PaymentGateway::class);
    }
}
