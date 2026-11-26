<?php

namespace Tests\Feature;

use App\Contracts\PushSender;
use App\Enums\PaymentMode;
use App\Events\ChatEvent;
use App\Models\DeviceToken;
use App\Models\Message;
use App\Models\Order;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Broadcast;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Tests\Concerns\BuildsOrders;
use Tests\TestCase;

class ChatTest extends TestCase
{
    use BuildsOrders, RefreshDatabase;

    /** @return array{Order, User, User} */
    private function assignedOrder(): array
    {
        $order = $this->confirmedOrder(PaymentMode::Cash);
        $courier = $this->courier();
        $order = $this->workflow()->assignCourier($order, $courier, $this->operator());

        return [$order, $order->restaurant, $courier];
    }

    private function text(string $body, ?string $uuid = null): array
    {
        return ['client_uuid' => $uuid ?? (string) Str::uuid(), 'type' => 'text', 'body' => $body];
    }

    public function test_the_client_and_the_courier_exchange_messages(): void
    {
        Event::fake([ChatEvent::class]);
        [$order, $client, $courier] = $this->assignedOrder();

        $this->actingAs($client)->postJson("/api/v1/orders/{$order->id}/messages", $this->text('Bonjour, le colis est au portail.'))
            ->assertCreated()
            ->assertJsonPath('type', 'text')
            ->assertJsonPath('sender_id', $client->id)
            ->assertJsonPath('read_at', null);

        Event::assertDispatched(ChatEvent::class, fn (ChatEvent $e) => $e->name === 'message.sent'
            && $e->broadcastOn()->name === "private-orders.{$order->id}");

        $this->actingAs($courier)->getJson("/api/v1/orders/{$order->id}/messages")
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('meta.can_send', true)
            ->assertJsonPath('meta.peer.id', $client->id)
            ->assertJsonPath('meta.peer.is_courier', false);

        // Récupéré par le livreur : reçu, pas encore lu.
        $message = Message::first();
        $this->assertNotNull($message->delivered_at);
        $this->assertNull($message->read_at);

        $this->actingAs($courier)->postJson("/api/v1/orders/{$order->id}/messages/receipt", ['read' => true, 'up_to_id' => $message->id])
            ->assertNoContent();

        $this->assertNotNull($message->fresh()->read_at);
        Event::assertDispatched(ChatEvent::class, fn (ChatEvent $e) => $e->name === 'message.receipt'
            && $e->payload['reader_id'] === $courier->id && $e->payload['read_at'] !== null);
    }

    public function test_reading_your_own_messages_does_not_mark_them_read(): void
    {
        [$order, $client] = $this->assignedOrder();

        $this->actingAs($client)->postJson("/api/v1/orders/{$order->id}/messages", $this->text('Je suis là'));
        $this->actingAs($client)->getJson("/api/v1/orders/{$order->id}/messages")->assertOk();
        $this->actingAs($client)->postJson("/api/v1/orders/{$order->id}/messages/receipt", ['read' => true]);

        $this->assertNull(Message::first()->delivered_at);
        $this->assertNull(Message::first()->read_at);
    }

    public function test_a_message_sent_again_after_a_network_cut_is_not_duplicated(): void
    {
        [$order, $client] = $this->assignedOrder();
        $payload = $this->text('Une seule fois');

        $this->actingAs($client)->postJson("/api/v1/orders/{$order->id}/messages", $payload)->assertCreated();
        $this->actingAs($client)->postJson("/api/v1/orders/{$order->id}/messages", $payload)->assertOk();

        $this->assertSame(1, Message::count());
    }

    public function test_the_chat_opens_only_once_a_courier_is_assigned(): void
    {
        $order = $this->confirmedOrder();

        $this->actingAs($order->restaurant)->postJson("/api/v1/orders/{$order->id}/messages", $this->text('Allô ?'))
            ->assertConflict();

        $this->actingAs($order->restaurant)->getJson("/api/v1/orders/{$order->id}/messages")
            ->assertOk()
            ->assertJsonPath('meta.can_send', false)
            ->assertJsonPath('meta.has_courier', false);
    }

    public function test_strangers_cannot_read_or_write(): void
    {
        [$order] = $this->assignedOrder();
        $stranger = $this->restaurant();
        $otherCourier = $this->courier();

        $this->actingAs($stranger)->getJson("/api/v1/orders/{$order->id}/messages")->assertForbidden();
        $this->actingAs($otherCourier)->postJson("/api/v1/orders/{$order->id}/messages", $this->text('Coucou'))->assertForbidden();
    }

    public function test_the_chat_becomes_read_only_once_delivered(): void
    {
        [$order, $client, $courier] = $this->assignedOrder();
        $this->actingAs($client)->postJson("/api/v1/orders/{$order->id}/messages", $this->text('Merci'));

        $order = $this->workflow()->startPreparing($order, $this->operator());
        $order = $this->workflow()->startDelivery($order, $courier);
        $this->workflow()->markDelivered($order, $courier);

        $this->actingAs($courier)->postJson("/api/v1/orders/{$order->id}/messages", $this->text('Livré'))->assertConflict();
        $this->actingAs($courier)->getJson("/api/v1/orders/{$order->id}/messages")
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('meta.can_send', false);
    }

    public function test_voice_photo_and_location_messages(): void
    {
        Storage::fake(config('superlivraison.media_disk'));
        [$order, $client, $courier] = $this->assignedOrder();

        $voice = $this->actingAs($courier)->postJson("/api/v1/orders/{$order->id}/messages", [
            'client_uuid' => (string) Str::uuid(),
            'type' => 'voice',
            'duration_seconds' => 4,
            'audio' => UploadedFile::fake()->create('vocal.m4a', 40, 'audio/mp4'),
        ])->assertCreated()->assertJsonPath('has_media', true)->assertJsonPath('duration_seconds', 4);

        $this->actingAs($courier)->postJson("/api/v1/orders/{$order->id}/messages", [
            'client_uuid' => (string) Str::uuid(),
            'type' => 'image',
            'image' => UploadedFile::fake()->image('portail.jpg'),
        ])->assertCreated()->assertJsonPath('type', 'image');

        $this->actingAs($courier)->postJson("/api/v1/orders/{$order->id}/messages", [
            'client_uuid' => (string) Str::uuid(),
            'type' => 'location',
            'lat' => 6.1725,
            'lng' => 1.2314,
        ])->assertCreated()->assertJsonPath('lat', 6.1725);

        $this->actingAs($client)->get('/api/v1/messages/'.$voice->json('id').'/media')->assertOk();
        $this->actingAs($this->restaurant())->getJson('/api/v1/messages/'.$voice->json('id').'/media')->assertForbidden();

        $this->actingAs($courier)->postJson("/api/v1/orders/{$order->id}/messages", [
            'client_uuid' => (string) Str::uuid(),
            'type' => 'voice',
        ])->assertUnprocessable()->assertJsonValidationErrors('audio');
    }

    public function test_the_recipient_phone_is_notified_and_unread_messages_are_counted(): void
    {
        $push = new class implements PushSender
        {
            public array $sent = [];

            public function send(string $token, string $title, string $body, array $data = []): void
            {
                $this->sent[] = compact('token', 'title', 'body', 'data');
            }

            public function sendData(string $token, array $data, int $ttlSeconds = 60): void {}
        };
        $this->app->instance(PushSender::class, $push);

        [$order, $client, $courier] = $this->assignedOrder();
        DeviceToken::forceCreate(['user_id' => $courier->id, 'token' => 'courier-phone', 'platform' => 'android']);

        $this->actingAs($client)->postJson("/api/v1/orders/{$order->id}/messages", $this->text('Le code du portail est 1234'));

        $this->assertCount(1, $push->sent);
        $this->assertSame('courier-phone', $push->sent[0]['token']);
        $this->assertSame('message', $push->sent[0]['data']['kind']);

        $this->actingAs($courier)->getJson('/api/v1/courier/deliveries')->assertJsonPath('0.unread_messages', 1);
        $this->actingAs($client)->getJson('/api/v1/orders')->assertJsonPath('data.0.unread_messages', 0);
    }

    public function test_only_people_of_the_order_join_its_live_channel(): void
    {
        config(['broadcasting.default' => 'reverb', 'broadcasting.connections.reverb.key' => 'k', 'broadcasting.connections.reverb.secret' => 's', 'broadcasting.connections.reverb.app_id' => 'a']);
        // Les canaux s'enregistrent sur le pilote actif : on les recharge sur celui des téléphones.
        Broadcast::forgetDrivers();
        require base_path('routes/channels.php');
        [$order, $client] = $this->assignedOrder();

        $this->actingAs($client)->postJson('/api/v1/broadcasting/auth', ['socket_id' => '123.456', 'channel_name' => "private-orders.{$order->id}"])
            ->assertOk()->assertJsonStructure(['auth']);

        $this->actingAs($this->restaurant())->postJson('/api/v1/broadcasting/auth', ['socket_id' => '123.456', 'channel_name' => "private-orders.{$order->id}"])
            ->assertForbidden();
    }
}
