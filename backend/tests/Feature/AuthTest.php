<?php

namespace Tests\Feature;

use App\Contracts\SmsSender;
use App\Enums\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\RateLimiter;
use Tests\TestCase;

class AuthTest extends TestCase
{
    use RefreshDatabase;

    private const PHONE = '+22890000001';

    private FakeSms $sms;

    protected function setUp(): void
    {
        parent::setUp();
        $this->sms = new FakeSms;
        $this->app->instance(SmsSender::class, $this->sms);
        RateLimiter::clear('otp-minute:'.self::PHONE);
    }

    private function requestCode(string $phone = self::PHONE)
    {
        RateLimiter::clear('otp-minute:'.$phone);

        return $this->postJson('/api/v1/auth/request-code', ['phone' => $phone]);
    }

    private function verify(string $code, string $phone = self::PHONE)
    {
        return $this->postJson('/api/v1/auth/verify-code', ['phone' => $phone, 'code' => $code, 'device_name' => 'test']);
    }

    public function test_a_new_user_logs_in_with_the_sms_code(): void
    {
        $this->requestCode()->assertStatus(202);

        $response = $this->verify($this->sms->code())->assertOk()->assertJsonPath('user.needs_setup', true);

        $this->assertNotEmpty($response->json('token'));
        $this->assertSame(Role::Restaurant, User::where('phone', self::PHONE)->first()->role);
        $this->getJson('/api/v1/me', ['Authorization' => 'Bearer '.$response->json('token')])->assertOk();
    }

    public function test_spaces_in_the_phone_number_are_ignored(): void
    {
        $this->requestCode('+228 90 00 00 01')->assertStatus(202);
        $this->assertSame(self::PHONE, $this->sms->phone);
    }

    public function test_an_invalid_phone_sends_nothing(): void
    {
        $this->postJson('/api/v1/auth/request-code', ['phone' => '90000001'])->assertStatus(422);
        $this->assertNull($this->sms->message);
    }

    public function test_a_second_request_within_a_minute_is_refused(): void
    {
        $this->postJson('/api/v1/auth/request-code', ['phone' => self::PHONE])->assertStatus(202);
        $this->postJson('/api/v1/auth/request-code', ['phone' => self::PHONE])->assertStatus(429);
    }

    public function test_a_code_works_only_once(): void
    {
        $this->requestCode();
        $code = $this->sms->code();

        $this->verify($code)->assertOk();
        $this->verify($code)->assertStatus(422);
    }

    public function test_a_code_expires(): void
    {
        $this->requestCode();
        $this->travel(6)->minutes();

        $this->verify($this->sms->code())->assertStatus(422);
    }

    public function test_the_code_is_blocked_after_too_many_mistakes(): void
    {
        $this->requestCode();
        $code = $this->sms->code();

        foreach (range(1, 5) as $i) {
            $this->verify($code === '000000' ? '111111' : '000000')->assertStatus(422);
        }

        $this->verify($code)->assertStatus(422);
    }

    public function test_a_new_code_replaces_the_previous_one(): void
    {
        $this->requestCode();
        $old = $this->sms->code();
        $this->requestCode();

        if ($old !== $this->sms->code()) {
            $this->verify($old)->assertStatus(422);
        }
        $this->verify($this->sms->code())->assertOk();
    }

    public function test_a_disabled_account_gets_no_sms_and_loses_api_access(): void
    {
        $user = User::factory()->inactive()->create(['phone' => self::PHONE]);
        $this->requestCode()->assertStatus(202);
        $this->assertNull($this->sms->message);

        $token = $user->createToken('t')->plainTextToken;
        $this->getJson('/api/v1/me', ['Authorization' => 'Bearer '.$token])->assertStatus(403);
    }

    public function test_staff_cannot_log_in_by_sms(): void
    {
        User::factory()->role(Role::Admin)->create(['phone' => self::PHONE]);
        $this->requestCode();

        $this->verify($this->sms->code())->assertStatus(403);
    }

    public function test_the_role_cannot_be_changed_through_the_profile(): void
    {
        $user = User::factory()->create();

        $this->actingAs($user)->patchJson('/api/v1/me', ['name' => 'Chez Ama', 'role' => 'admin', 'is_active' => false])->assertOk();

        $user->refresh();
        $this->assertSame('Chez Ama', $user->name);
        $this->assertSame(Role::Restaurant, $user->role);
        $this->assertTrue($user->is_active);
    }

    public function test_logout_revokes_the_token(): void
    {
        $user = User::factory()->create();
        $token = $user->createToken('t')->plainTextToken;

        $this->postJson('/api/v1/auth/logout', [], ['Authorization' => 'Bearer '.$token])->assertNoContent();

        $this->assertSame(0, $user->tokens()->count());
    }
}

class FakeSms implements SmsSender
{
    public ?string $phone = null;

    public ?string $message = null;

    public function send(string $phone, string $message): void
    {
        $this->phone = $phone;
        $this->message = $message;
    }

    public function code(): string
    {
        preg_match('/\d{6}/', (string) $this->message, $m);

        return $m[0];
    }
}
