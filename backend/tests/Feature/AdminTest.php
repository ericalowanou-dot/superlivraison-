<?php

namespace Tests\Feature;

use App\Enums\OrderStatus;
use App\Enums\PaymentMode;
use App\Enums\PaymentStatus;
use App\Enums\Role;
use App\Filament\Resources\Orders\Pages\ViewOrder;
use App\Filament\Resources\Payments\Pages\ListPayments;
use App\Filament\Resources\Users\Pages\CreateUser;
use App\Filament\Resources\Users\Pages\EditUser;
use App\Filament\Widgets\OverviewStats;
use App\Models\User;
use App\Services\PaymentService;
use Filament\Facades\Filament;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\Concerns\BuildsOrders;
use Tests\TestCase;

class AdminTest extends TestCase
{
    use BuildsOrders, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Filament::setCurrentPanel(Filament::getPanel('admin'));
    }

    private function admin(): User
    {
        return User::factory()->role(Role::Admin)->create(['email' => fake()->unique()->safeEmail()]);
    }

    public function test_a_restaurant_cannot_enter_the_administration(): void
    {
        $this->actingAs($this->restaurant())->get('/admin')->assertForbidden();
    }

    public function test_guests_are_sent_to_the_login_page(): void
    {
        $this->get('/admin')->assertRedirect('/admin/login');
        $this->get('/admin-media/orders/1/voice')->assertRedirect('/admin/login');
    }

    public function test_every_page_opens_for_an_admin(): void
    {
        $order = $this->confirmedOrder(PaymentMode::Cash);
        $this->actingAs($this->admin());

        foreach (['/admin', '/admin/orders', "/admin/orders/{$order->id}", '/admin/payments', '/admin/users', '/admin/users/create', '/admin/countries', '/admin/cities', '/admin/languages'] as $url) {
            $this->get($url)->assertOk();
        }
    }

    public function test_an_operator_only_sees_the_operational_pages(): void
    {
        $this->actingAs($this->operator());

        foreach (['/admin', '/admin/orders', '/admin/payments'] as $url) {
            $this->get($url)->assertOk();
        }
        foreach (['/admin/users', '/admin/countries', '/admin/cities', '/admin/languages'] as $url) {
            $this->get($url)->assertForbidden();
        }
    }

    public function test_an_operator_prices_and_ships_an_order(): void
    {
        $operator = $this->operator();
        $courier = $this->courier();
        $order = $this->newOrder();
        $this->actingAs($operator);

        Livewire::test(ViewOrder::class, ['record' => $order->id])->callAction('setPrice', ['price' => 7500])->assertHasNoActionErrors();
        $this->assertSame(OrderStatus::PricePending, $order->fresh()->status);
        $this->assertSame(7500, $order->fresh()->price);

        $order = $this->workflow()->acceptPrice($order->fresh(), $order->restaurant, PaymentMode::Cash, 7500);

        Livewire::test(ViewOrder::class, ['record' => $order->id])->callAction('assignCourier', ['courier_id' => $courier->id]);
        Livewire::test(ViewOrder::class, ['record' => $order->id])->callAction('startPreparing');
        Livewire::test(ViewOrder::class, ['record' => $order->id])->callAction('startDelivery');
        Livewire::test(ViewOrder::class, ['record' => $order->id])->callAction('markDelivered');

        $this->assertSame(OrderStatus::Delivered, $order->fresh()->status);
        $this->assertTrue($order->fresh()->isPaid());
    }

    public function test_a_refused_step_shows_an_error_instead_of_crashing(): void
    {
        $order = $this->confirmedOrder(PaymentMode::MobileMoney);
        $this->actingAs($this->operator());

        Livewire::test(ViewOrder::class, ['record' => $order->id])->callAction('startPreparing')->assertNotified('Le paiement mobile doit être reçu avant la préparation.');

        $this->assertSame(OrderStatus::Confirmed, $order->fresh()->status);
    }

    public function test_only_an_admin_refunds(): void
    {
        $order = $this->confirmedOrder(PaymentMode::Cash);
        $payment = $order->payments()->first();
        app(PaymentService::class)->confirmCash($order);

        $this->actingAs($this->operator());
        Livewire::test(ListPayments::class)->assertTableActionHidden('refund', $payment->fresh());

        $this->actingAs($this->admin());
        Livewire::test(ListPayments::class)->callTableAction('refund', $payment->fresh());
        $this->assertSame(PaymentStatus::Refunded, $payment->fresh()->status);
    }

    public function test_an_admin_creates_a_courier(): void
    {
        $this->actingAs($this->admin());

        Livewire::test(CreateUser::class)
            ->fillForm(['role' => Role::Courier->value, 'name' => 'Kossi', 'phone' => '+22891000000', 'is_active' => true])
            ->call('create')
            ->assertHasNoFormErrors();

        $this->assertSame(Role::Courier, User::where('phone', '+22891000000')->first()->role);
    }

    public function test_disabling_an_account_revokes_its_tokens(): void
    {
        $courier = $this->courier();
        $courier->createToken('t');
        $this->actingAs($this->admin());

        Livewire::test(EditUser::class, ['record' => $courier->id])
            ->fillForm(['is_active' => false])
            ->call('save')
            ->assertHasNoFormErrors();

        $this->assertFalse($courier->fresh()->is_active);
        $this->assertSame(0, $courier->tokens()->count());
    }

    public function test_an_admin_cannot_demote_or_disable_themselves(): void
    {
        $admin = $this->admin();
        $this->actingAs($admin);

        Livewire::test(EditUser::class, ['record' => $admin->id])
            ->fillForm(['role' => Role::Restaurant->value, 'is_active' => false])
            ->call('save');

        $this->assertSame(Role::Admin, $admin->fresh()->role);
        $this->assertTrue($admin->fresh()->is_active);
    }

    public function test_the_operator_can_listen_to_a_voice_order_but_a_stranger_cannot(): void
    {
        $order = $this->newOrder();

        $this->actingAs($this->restaurant())->get("/admin-media/orders/{$order->id}/voice")->assertForbidden();
        $this->actingAs($this->operator())->get("/admin-media/orders/{$order->id}/voice")->assertNotFound();
    }

    public function test_the_dashboard_widget_renders(): void
    {
        $this->newOrder();
        $this->actingAs($this->admin());

        Livewire::test(OverviewStats::class)->assertSee('Demandes à chiffrer');
    }
}
