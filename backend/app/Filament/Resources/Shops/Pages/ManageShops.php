<?php

namespace App\Filament\Resources\Shops\Pages;

use App\Enums\ReviewStatus;
use App\Filament\Resources\Shops\ShopResource;
use App\Models\Shop;
use Filament\Actions\CreateAction;
use Filament\Resources\Pages\ManageRecords;

class ManageShops extends ManageRecords
{
    protected static string $resource = ShopResource::class;

    protected function getHeaderActions(): array
    {
        // Une boutique créée par l'équipe n'a pas à être validée.
        return [
            CreateAction::make()
                ->after(fn (Shop $record) => $record->forceFill(['status' => ReviewStatus::Approved, 'approved_at' => now()])->save()),
        ];
    }
}
