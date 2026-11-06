<?php

namespace Tests\Feature;

use App\Enums\ReviewStatus;
use App\Enums\Role;
use App\Filament\Resources\Ads\Pages\ManageAds;
use App\Filament\Resources\Shops\Pages\ManageShops;
use App\Models\Ad;
use App\Models\City;
use App\Models\Shop;
use App\Models\User;
use App\Services\AdModeration;
use Filament\Actions\Testing\TestAction;
use Filament\Facades\Filament;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Livewire\Livewire;
use Tests\Concerns\BuildsOrders;
use Tests\TestCase;

class AdsAndShopsTest extends TestCase
{
    use BuildsOrders, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake(config('superlivraison.media_disk'));
    }

    private function submit(?User $user = null): Ad
    {
        $this->actingAs($user ?? $this->restaurant())->post('/api/v1/ads', [
            'category' => 'concert',
            'title' => 'Concert à Lomé',
            'image' => UploadedFile::fake()->image('affiche.jpg'),
        ], ['Accept' => 'application/json'])->assertCreated();

        return Ad::latest('id')->first();
    }

    public function test_a_submitted_ad_stays_hidden_until_it_is_approved(): void
    {
        $operator = $this->operator();
        $author = $this->restaurant();
        $reader = $this->restaurant();

        $ad = $this->submit($author);
        $this->assertSame(ReviewStatus::Pending, $ad->status);
        $this->assertSame(1, $operator->notifications()->count());

        $this->actingAs($reader)->getJson('/api/v1/ads')->assertJsonCount(0, 'data');
        $this->actingAs($reader)->get("/api/v1/ads/{$ad->id}/image")->assertNotFound();
        $this->actingAs($author)->getJson('/api/v1/ads/mine')->assertJsonPath('data.0.status', 'pending');
        $this->actingAs($author)->get("/api/v1/ads/{$ad->id}/image")->assertOk();

        app(AdModeration::class)->approve($ad);

        $this->actingAs($reader)->getJson('/api/v1/ads')->assertJsonCount(1, 'data')->assertJsonPath('data.0.is_mine', false);
        $this->actingAs($reader)->get("/api/v1/ads/{$ad->id}/image")->assertOk();
        $this->assertSame(1, $author->notifications()->count());
    }

    public function test_a_rejected_ad_shows_its_reason_to_the_author(): void
    {
        $author = $this->restaurant();
        $ad = $this->submit($author);

        app(AdModeration::class)->reject($ad, 'Image illisible');

        $this->actingAs($author)->getJson('/api/v1/ads/mine')->assertJsonPath('data.0.rejection_reason', 'Image illisible');
        $this->getJson('/api/v1/ads')->assertJsonCount(0, 'data');
    }

    public function test_ads_are_limited_to_the_reader_city(): void
    {
        $ad = $this->submit();
        app(AdModeration::class)->approve($ad);

        $other = City::create(['country_id' => $this->city()->country_id, 'name' => 'Kara']);
        $reader = User::factory()->create(['city_id' => $other->id]);

        $this->actingAs($reader)->getJson('/api/v1/ads')->assertJsonCount(0, 'data');
    }

    public function test_only_images_are_accepted(): void
    {
        $this->actingAs($this->restaurant())->post('/api/v1/ads', [
            'category' => 'advert',
            'title' => 'Promotion',
            'image' => UploadedFile::fake()->create('virus.pdf', 10, 'application/pdf'),
        ], ['Accept' => 'application/json'])->assertUnprocessable()->assertJsonValidationErrors('image');
    }

    public function test_only_the_author_can_delete_an_ad(): void
    {
        $author = $this->restaurant();
        $ad = $this->submit($author);

        $this->actingAs($this->restaurant())->deleteJson("/api/v1/ads/{$ad->id}")->assertNotFound();
        $this->actingAs($author)->deleteJson("/api/v1/ads/{$ad->id}")->assertNoContent();

        $this->assertSame(0, Ad::count());
        Storage::disk(config('superlivraison.media_disk'))->assertMissing($ad->image_path);
    }

    public function test_shops_are_listed_by_city_and_searchable(): void
    {
        $city = $this->city();
        $other = City::create(['country_id' => $city->country_id, 'name' => 'Kara']);
        $open = fn (array $data) => tap(Shop::create($data), fn (Shop $shop) => $shop->forceFill(['status' => ReviewStatus::Approved])->save());
        $open(['city_id' => $city->id, 'name' => 'Boutique Afia', 'category' => 'Épicerie', 'phone' => '+22890000001']);
        $open(['city_id' => $city->id, 'name' => 'Mode Kodjo', 'category' => 'Vêtements']);
        $open(['city_id' => $city->id, 'name' => 'Cachée', 'is_active' => false]);
        $open(['city_id' => $other->id, 'name' => 'Boutique de Kara']);

        $this->actingAs($this->restaurant());

        $this->getJson('/api/v1/shops')->assertJsonCount(2, 'data')->assertJsonPath('data.0.name', 'Boutique Afia');
        $this->getJson('/api/v1/shops?search=Vêt')->assertJsonCount(1, 'data')->assertJsonPath('data.0.name', 'Mode Kodjo');
    }

    public function test_the_team_moderates_ads_and_manages_shops_from_the_administration(): void
    {
        Filament::setCurrentPanel(Filament::getPanel('admin'));
        $admin = User::factory()->role(Role::Admin)->create(['email' => fake()->unique()->safeEmail()]);
        $ad = $this->submit();

        $this->actingAs($admin);

        Livewire::test(ManageAds::class)
            ->assertCanSeeTableRecords([$ad])
            ->callAction(TestAction::make('reject')->table($ad), ['reason' => 'Hors sujet'])
            ->assertHasNoActionErrors();
        $this->assertSame(ReviewStatus::Rejected, $ad->refresh()->status);

        Livewire::test(ManageAds::class)->callAction(TestAction::make('approve')->table($ad));
        $this->assertSame(ReviewStatus::Approved, $ad->refresh()->status);

        Livewire::test(ManageShops::class)->assertOk();
    }
}
