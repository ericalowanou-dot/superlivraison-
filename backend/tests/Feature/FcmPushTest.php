<?php

namespace Tests\Feature;

use App\Models\DeviceToken;
use App\Services\Drivers\FcmPushSender;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\Concerns\BuildsOrders;
use Tests\TestCase;

class FcmPushTest extends TestCase
{
    use BuildsOrders, RefreshDatabase;

    private string $keyFile;

    protected function setUp(): void
    {
        parent::setUp();

        $key = openssl_pkey_new(['private_key_bits' => 2048, 'private_key_type' => OPENSSL_KEYTYPE_RSA]);
        openssl_pkey_export($key, $pem);

        $this->keyFile = tempnam(sys_get_temp_dir(), 'fcm');
        file_put_contents($this->keyFile, json_encode([
            'project_id' => 'superlivraison-test',
            'client_email' => 'push@superlivraison-test.iam.gserviceaccount.com',
            'private_key' => $pem,
            'token_uri' => 'https://oauth2.googleapis.com/token',
        ]));
    }

    protected function tearDown(): void
    {
        @unlink($this->keyFile);
        parent::tearDown();
    }

    public function test_a_notification_reaches_firebase_with_a_signed_access_token(): void
    {
        Http::fake([
            'oauth2.googleapis.com/*' => Http::response(['access_token' => 'jeton-google', 'expires_in' => 3600]),
            'fcm.googleapis.com/*' => Http::response(['name' => 'projects/superlivraison-test/messages/1']),
        ]);

        $sender = new FcmPushSender($this->keyFile);
        $sender->send('telephone-1', 'Nouveau message', 'Je suis au portail', ['kind' => 'message', 'order_id' => '12']);
        $sender->send('telephone-1', 'Nouveau message', 'Encore moi', []);

        // Le jeton d'accès est réutilisé : une seule demande à Google pour deux notifications.
        Http::assertSentCount(3);
        Http::assertSent(function (Request $request) {
            if (! str_contains($request->url(), 'oauth2')) {
                return false;
            }
            [$header, $claims] = array_map(fn ($part) => json_decode(base64_decode(strtr($part, '-_', '+/')), true), explode('.', $request['assertion']));

            return $header['alg'] === 'RS256' && $claims['scope'] === 'https://www.googleapis.com/auth/firebase.messaging';
        });
        Http::assertSent(fn (Request $request) => $request->url() === 'https://fcm.googleapis.com/v1/projects/superlivraison-test/messages:send'
            && $request->hasHeader('Authorization', 'Bearer jeton-google')
            && $request['message']['token'] === 'telephone-1'
            && $request['message']['notification']['body'] === 'Je suis au portail'
            && $request['message']['android']['notification']['channel_id'] === 'superlivraison'
            && $request['message']['data'] === ['kind' => 'message', 'order_id' => '12']);
    }

    public function test_a_token_of_an_uninstalled_app_is_forgotten(): void
    {
        $user = $this->restaurant();
        DeviceToken::forceCreate(['user_id' => $user->id, 'token' => 'ancien-telephone', 'platform' => 'android']);

        Http::fake([
            'oauth2.googleapis.com/*' => Http::response(['access_token' => 'jeton-google']),
            'fcm.googleapis.com/*' => Http::response(['error' => [
                'status' => 'NOT_FOUND',
                'details' => [['errorCode' => 'UNREGISTERED']],
            ]], 404),
        ]);

        (new FcmPushSender($this->keyFile))->send('ancien-telephone', 'Titre', 'Texte');

        $this->assertSame(0, DeviceToken::count());
    }

    public function test_a_missing_key_is_reported_clearly(): void
    {
        $this->expectExceptionMessage('FIREBASE_CREDENTIALS');

        new FcmPushSender('/nulle/part/firebase.json');
    }

    public function test_logging_out_stops_the_notifications_of_this_phone(): void
    {
        $user = $this->restaurant();
        DeviceToken::forceCreate(['user_id' => $user->id, 'token' => 'ce-telephone', 'platform' => 'android']);
        DeviceToken::forceCreate(['user_id' => $user->id, 'token' => 'autre-telephone', 'platform' => 'ios']);
        $token = $user->createToken('t')->plainTextToken;

        $this->withToken($token)->postJson('/api/v1/auth/logout', ['device_token' => 'ce-telephone'])->assertNoContent();

        $this->assertSame(['autre-telephone'], DeviceToken::pluck('token')->all());
    }
}
