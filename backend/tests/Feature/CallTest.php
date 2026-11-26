<?php

namespace Tests\Feature;

use App\Contracts\PushSender;
use App\Enums\PaymentMode;
use App\Events\ChatEvent;
use App\Jobs\ExpireCall;
use App\Models\Call;
use App\Models\DeviceToken;
use App\Models\Order;
use App\Models\User;
use App\Services\Calls;
use App\Services\ZegoToken;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Bus;
use Illuminate\Support\Facades\Event;
use Tests\Concerns\BuildsOrders;
use Tests\TestCase;

class CallTest extends TestCase
{
    use BuildsOrders, RefreshDatabase;

    private const SECRET = '0123456789abcdef0123456789abcdef';

    /** @var object{sent: array, data: array} */
    private object $push;

    protected function setUp(): void
    {
        parent::setUp();
        config(['superlivraison.zego.app_id' => 12345678, 'superlivraison.zego.server_secret' => self::SECRET]);

        $this->push = new class implements PushSender
        {
            public array $sent = [];

            public array $data = [];

            public function send(string $token, string $title, string $body, array $data = []): void
            {
                $this->sent[] = compact('token', 'title', 'body', 'data');
            }

            public function sendData(string $token, array $data, int $ttlSeconds = 60): void
            {
                $this->data[] = compact('token', 'data');
            }
        };
        $this->app->instance(PushSender::class, $this->push);
    }

    /** @return array{Order, User, User} */
    private function assignedOrder(): array
    {
        $order = $this->confirmedOrder(PaymentMode::Cash);
        $courier = $this->courier();
        $order = $this->workflow()->assignCourier($order, $courier, $this->operator());
        DeviceToken::forceCreate(['user_id' => $courier->id, 'token' => 'courier-phone', 'platform' => 'android']);

        return [$order, $order->restaurant, $courier];
    }

    private function startCall(Order $order, User $caller, bool $video = true): Call
    {
        $id = $this->actingAs($caller)->postJson("/api/v1/orders/{$order->id}/calls", ['video' => $video])
            ->assertCreated()
            ->json('call.id');

        return Call::findOrFail($id);
    }

    public function test_a_call_rings_the_other_phone_and_gives_a_token_instead_of_the_secret(): void
    {
        Event::fake([ChatEvent::class]);
        config(['queue.default' => 'database']);
        Bus::fake([ExpireCall::class]);
        [$order, $client, $courier] = $this->assignedOrder();

        $response = $this->actingAs($client)->postJson("/api/v1/orders/{$order->id}/calls", ['video' => true])
            ->assertCreated()
            ->assertJsonPath('call.status', 'ringing')
            ->assertJsonPath('call.video', true)
            ->assertJsonPath('peer.id', $courier->id)
            ->assertJsonPath('zego.app_id', 12345678)
            ->assertJsonPath('zego.user_id', 'u'.$client->id);

        $callId = $response->json('call.id');
        $this->assertSame("call_{$callId}", $response->json('zego.room_id'));
        $this->assertSame("call_{$callId}_u{$courier->id}", $response->json('zego.peer_stream_id'));
        $this->assertStringNotContainsString(self::SECRET, $response->getContent());

        Event::assertDispatched(ChatEvent::class, fn (ChatEvent $e) => $e->name === 'call.ringing');
        Bus::assertDispatched(ExpireCall::class, fn (ExpireCall $job) => $job->callId === $callId);

        $this->assertCount(1, $this->push->data);
        $this->assertSame('courier-phone', $this->push->data[0]['token']);
        $this->assertSame('call', $this->push->data[0]['data']['kind']);
        $this->assertSame('1', $this->push->data[0]['data']['video']);
    }

    public function test_the_token_follows_the_zegocloud_format(): void
    {
        $token = (new ZegoToken(12345678, self::SECRET))->generate('u7', 3600);

        $this->assertStringStartsWith('04', $token);
        $binary = base64_decode(substr($token, 2), true);
        $expire = unpack('J', substr($binary, 0, 8))[1];
        $ivLength = unpack('n', substr($binary, 8, 2))[1];
        $iv = substr($binary, 10, $ivLength);
        $length = unpack('n', substr($binary, 10 + $ivLength, 2))[1];
        $cipher = substr($binary, 12 + $ivLength, $length);

        $this->assertSame(16, $ivLength);
        $this->assertSame(strlen($binary), 12 + $ivLength + $length);

        $plain = json_decode(openssl_decrypt($cipher, 'aes-256-cbc', self::SECRET, OPENSSL_RAW_DATA, $iv), true);
        $this->assertSame(12345678, $plain['app_id']);
        $this->assertSame('u7', $plain['user_id']);
        $this->assertSame('', $plain['payload']);
        $this->assertSame($expire, $plain['expire']);
        $this->assertSame(3600, $plain['expire'] - $plain['ctime']);
    }

    public function test_the_callee_answers_then_hangs_up_and_the_chat_keeps_a_trace(): void
    {
        Bus::fake([ExpireCall::class]);
        [$order, $client, $courier] = $this->assignedOrder();
        $call = $this->startCall($order, $client);

        // L'appelant ne peut pas décrocher à la place de l'autre.
        $this->actingAs($client)->postJson("/api/v1/calls/{$call->id}/accept")->assertConflict();

        $this->actingAs($courier)->postJson("/api/v1/calls/{$call->id}/accept")
            ->assertOk()
            ->assertJsonPath('call.status', 'ongoing')
            ->assertJsonPath('zego.user_id', 'u'.$courier->id)
            ->assertJsonPath('zego.peer_stream_id', "call_{$call->id}_u{$client->id}");

        $this->travel(75)->seconds();

        $this->actingAs($client)->postJson("/api/v1/calls/{$call->id}/end")
            ->assertOk()
            ->assertJsonPath('call.status', 'ended')
            ->assertJsonPath('call.duration_seconds', 75);

        $this->actingAs($courier)->getJson("/api/v1/orders/{$order->id}/messages")
            ->assertOk()
            ->assertJsonPath('data.0.type', 'call')
            ->assertJsonPath('data.0.sender_id', $client->id)
            ->assertJsonPath('data.0.call.video', true)
            ->assertJsonPath('data.0.call.status', 'ended')
            ->assertJsonPath('data.0.call.duration_seconds', 75);

        // Raccrocher deux fois ne crée pas de deuxième trace.
        $this->actingAs($courier)->postJson("/api/v1/calls/{$call->id}/end")->assertOk();
        $this->assertSame(1, $order->messages()->count());
        $this->assertSame([], $this->push->sent);
    }

    public function test_an_unanswered_call_becomes_missed_and_notifies_the_callee(): void
    {
        Bus::fake([ExpireCall::class]);
        [$order, $client] = $this->assignedOrder();
        $call = $this->startCall($order, $client, video: false);

        (new ExpireCall($call->id))->handle(app(Calls::class));

        $this->assertSame('missed', $call->fresh()->status->value);
        $this->assertSame('call_ended', $this->push->data[1]['data']['kind']);
        $this->assertCount(1, $this->push->sent);
        $this->assertSame('Appel vocal manqué', $this->push->sent[0]['body']);

        // Trop tard pour décrocher.
        $this->actingAs($order->courier)->postJson("/api/v1/calls/{$call->id}/accept")->assertConflict();
    }

    public function test_without_a_queue_worker_a_stale_ringing_call_expires_when_read(): void
    {
        [$order, $client, $courier] = $this->assignedOrder();
        $call = $this->startCall($order, $client);
        $this->actingAs($courier)->getJson("/api/v1/calls/{$call->id}")->assertJsonPath('call.status', 'ringing');

        $this->travel(46)->seconds();

        $this->actingAs($client)->getJson("/api/v1/calls/{$call->id}")->assertJsonPath('call.status', 'missed');
        $this->actingAs($courier)->postJson("/api/v1/calls/{$call->id}/accept")->assertConflict();
        // Le suivant peut appeler de nouveau.
        $this->startCall($order, $courier);
    }

    public function test_the_callee_declines(): void
    {
        Bus::fake([ExpireCall::class]);
        [$order, $client, $courier] = $this->assignedOrder();
        $call = $this->startCall($order, $client);

        $this->actingAs($courier)->postJson("/api/v1/calls/{$call->id}/end")
            ->assertOk()
            ->assertJsonPath('call.status', 'declined');
        $this->assertSame([], $this->push->sent);
    }

    public function test_only_one_call_at_a_time_and_only_between_the_two_participants(): void
    {
        Bus::fake([ExpireCall::class]);
        [$order, $client, $courier] = $this->assignedOrder();
        $call = $this->startCall($order, $client);

        $this->actingAs($courier)->postJson("/api/v1/orders/{$order->id}/calls", ['video' => false])->assertConflict();

        $stranger = User::factory()->create();
        $this->actingAs($stranger)->getJson("/api/v1/calls/{$call->id}")->assertNotFound();
        $this->actingAs($stranger)->postJson("/api/v1/calls/{$call->id}/accept")->assertNotFound();
    }

    public function test_no_call_before_a_courier_is_assigned_or_without_configuration(): void
    {
        $order = $this->confirmedOrder(PaymentMode::Cash);
        $this->actingAs($order->restaurant)->postJson("/api/v1/orders/{$order->id}/calls", ['video' => false])->assertConflict();

        [$order, $client] = $this->assignedOrder();
        config(['superlivraison.zego.server_secret' => '']);
        $this->actingAs($client)->postJson("/api/v1/orders/{$order->id}/calls", ['video' => false])
            ->assertConflict()
            ->assertJsonPath('message', 'Les appels ne sont pas encore disponibles.');
    }
}
