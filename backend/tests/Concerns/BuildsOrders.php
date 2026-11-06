<?php

namespace Tests\Concerns;

use App\Enums\PaymentMode;
use App\Enums\Role;
use App\Models\City;
use App\Models\Country;
use App\Models\Order;
use App\Models\User;
use App\Services\OrderWorkflow;
use Illuminate\Support\Str;

trait BuildsOrders
{
    protected function city(): City
    {
        $country = Country::firstOrCreate(['code' => 'TG'], ['name' => 'Togo', 'dial_code' => '+228']);

        return City::firstOrCreate(['country_id' => $country->id, 'name' => 'Lomé']);
    }

    protected function restaurant(): User
    {
        return User::factory()->create(['city_id' => $this->city()->id]);
    }

    protected function operator(): User
    {
        return User::factory()->role(Role::Operator)->create();
    }

    protected function courier(): User
    {
        return User::factory()->role(Role::Courier)->create();
    }

    protected function workflow(): OrderWorkflow
    {
        return app(OrderWorkflow::class);
    }

    protected function newOrder(?User $restaurant = null): Order
    {
        return $this->workflow()->create($restaurant ?? $this->restaurant(), [
            'client_uuid' => (string) Str::uuid(),
            'channel' => 'text',
            'request_text' => '20 kg de riz',
            'delivery_landmark' => 'Face à la pharmacie',
        ]);
    }

    protected function confirmedOrder(PaymentMode $mode = PaymentMode::MobileMoney, int $price = 5000): Order
    {
        $order = $this->workflow()->setPrice($this->newOrder(), $price, $this->operator());

        return $this->workflow()->acceptPrice($order, $order->restaurant, $mode, $price);
    }
}
