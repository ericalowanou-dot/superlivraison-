<?php

namespace App\Filament\Resources\Ads\Pages;

use App\Enums\ReviewStatus;
use App\Filament\Resources\Ads\AdResource;
use App\Models\Ad;
use Filament\Actions\CreateAction;
use Filament\Resources\Pages\ManageRecords;

class ManageAds extends ManageRecords
{
    protected static string $resource = AdResource::class;

    protected function getHeaderActions(): array
    {
        return [
            // Une publicité créée par l'équipe n'a pas à être validée.
            CreateAction::make()
                ->mutateDataUsing(fn (array $data) => [...$data, 'user_id' => auth()->id()])
                ->after(fn (Ad $record) => $record->forceFill(['status' => ReviewStatus::Approved, 'approved_at' => now()])->save()),
        ];
    }
}
