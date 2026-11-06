<?php

namespace App\Policies;

use App\Enums\Role;
use App\Models\Order;
use App\Models\User;

class OrderPolicy
{
    public function viewAny(User $user): bool
    {
        return $user->isStaff();
    }

    public function view(User $user, Order $order): bool
    {
        return $user->isStaff() || $this->owns($user, $order) || $this->delivers($user, $order);
    }

    public function create(User $user): bool
    {
        return $user->role === Role::Restaurant;
    }

    public function update(User $user, Order $order): bool
    {
        return $user->isStaff();
    }

    public function delete(User $user, Order $order): bool
    {
        return false;
    }

    public function respond(User $user, Order $order): bool
    {
        return $this->owns($user, $order);
    }

    public function deliver(User $user, Order $order): bool
    {
        return $this->delivers($user, $order);
    }

    private function owns(User $user, Order $order): bool
    {
        return $user->id === $order->restaurant_id;
    }

    private function delivers(User $user, Order $order): bool
    {
        return $user->role === Role::Courier && $user->id === $order->courier_id;
    }
}
