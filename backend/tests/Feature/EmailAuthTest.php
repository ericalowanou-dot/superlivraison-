<?php

namespace Tests\Feature;

use App\Enums\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\RateLimiter;
use Tests\TestCase;

class EmailAuthTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        RateLimiter::clear('auth-ip:127.0.0.1');
    }

    private function register(array $overrides = [])
    {
        return $this->postJson('/api/v1/auth/register', array_merge([
            'name' => 'Ama Mensah',
            'email' => 'Ama@Exemple.tg ',
            'phone' => '+228 90 11 22 33',
            'password' => 'motdepasse',
            'password_confirmation' => 'motdepasse',
            'device_name' => 'test',
        ], $overrides));
    }

    private function login(string $email, string $password)
    {
        return $this->postJson('/api/v1/auth/login', ['email' => $email, 'password' => $password, 'device_name' => 'test']);
    }

    public function test_a_new_user_creates_an_account_and_is_signed_in(): void
    {
        $response = $this->register()->assertCreated()
            ->assertJsonPath('user.email', 'ama@exemple.tg')
            ->assertJsonPath('user.name', 'Ama Mensah')
            ->assertJsonPath('user.phone', '+22890112233')
            ->assertJsonPath('user.needs_setup', true);

        $this->withToken($response->json('token'))->getJson('/api/v1/me')->assertOk();
        $this->assertNotSame('motdepasse', User::first()->password);
    }

    public function test_the_phone_is_optional(): void
    {
        $this->register(['phone' => null])->assertCreated()->assertJsonPath('user.phone', null);
    }

    public function test_an_email_can_only_be_used_once(): void
    {
        $this->register()->assertCreated();

        $this->register(['email' => 'ama@exemple.tg', 'phone' => null])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['email' => 'Un compte existe déjà avec cette adresse e-mail.']);
    }

    public function test_the_password_must_be_long_enough_and_confirmed(): void
    {
        $this->register(['password' => 'court', 'password_confirmation' => 'court'])->assertJsonValidationErrors('password');
        $this->register(['password_confirmation' => 'autrechose'])->assertJsonValidationErrors('password');
    }

    public function test_an_invalid_phone_is_refused(): void
    {
        $this->register(['phone' => '12'])->assertJsonValidationErrors('phone');
    }

    public function test_a_user_signs_in_with_email_and_password(): void
    {
        $this->register()->assertCreated();

        $this->login(' AMA@exemple.tg', 'motdepasse')->assertOk()
            ->assertJsonPath('user.email', 'ama@exemple.tg')
            ->assertJsonStructure(['token']);
    }

    public function test_a_wrong_password_is_refused_without_saying_which_field_is_wrong(): void
    {
        $this->register()->assertCreated();

        $this->login('ama@exemple.tg', 'mauvais')->assertJsonValidationErrors(['email' => 'E-mail ou mot de passe incorrect.']);
        $this->login('inconnu@exemple.tg', 'motdepasse')->assertJsonValidationErrors(['email' => 'E-mail ou mot de passe incorrect.']);
    }

    public function test_staff_and_disabled_accounts_cannot_sign_in_to_the_app(): void
    {
        User::factory()->role(Role::Admin)->create(['email' => 'admin@exemple.tg', 'password' => 'motdepasse']);
        User::factory()->create(['email' => 'bloque@exemple.tg', 'password' => 'motdepasse', 'is_active' => false]);

        $this->login('admin@exemple.tg', 'motdepasse')->assertForbidden();
        $this->login('bloque@exemple.tg', 'motdepasse')->assertForbidden();
    }

    public function test_repeated_wrong_passwords_are_slowed_down(): void
    {
        foreach (range(1, 5) as $i) {
            $this->login('ama@exemple.tg', 'mauvais'.$i);
        }

        $this->login('ama@exemple.tg', 'encore')->assertTooManyRequests();
    }
}
