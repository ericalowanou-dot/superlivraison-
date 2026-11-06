<?php

namespace Database\Factories;

use App\Enums\Role;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<User> */
class UserFactory extends Factory
{
    public function definition(): array
    {
        return [
            'phone' => '+2289'.fake()->unique()->numerify('#######'),
            'name' => fake()->name(),
        ];
    }

    public function role(Role $role): static
    {
        return $this->afterMaking(fn (User $user) => $user->role = $role)
            ->afterCreating(fn (User $user) => $user->refresh());
    }

    public function inactive(): static
    {
        return $this->afterMaking(fn (User $user) => $user->is_active = false);
    }
}
