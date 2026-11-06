<?php

namespace App\Filament\Resources\Payouts;

use App\Enums\PayoutStatus;
use App\Filament\Resources\Payouts\Pages\ListPayouts;
use App\Models\Payout;
use App\Services\ShopPayouts;
use BackedEnum;
use Filament\Actions\Action;
use Filament\Forms\Components\TextInput;
use Filament\Resources\Resource;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;

class PayoutResource extends Resource
{
    protected static ?string $model = Payout::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedArrowsRightLeft;

    protected static ?string $navigationLabel = 'Reversements';

    protected static ?string $modelLabel = 'reversement';

    protected static ?string $pluralModelLabel = 'reversements';

    public static function canCreate(): bool
    {
        return false;
    }

    public static function canAccess(): bool
    {
        return auth()->user()?->isAdmin() ?? false;
    }

    public static function getNavigationBadge(): ?string
    {
        $pending = Payout::where('status', PayoutStatus::Pending)->count();

        return $pending > 0 ? (string) $pending : null;
    }

    public static function table(Table $table): Table
    {
        return $table
            ->defaultSort('id', 'desc')
            ->modifyQueryUsing(fn ($query) => $query->with(['shop', 'order']))
            ->columns([
                TextColumn::make('shop.name')->label('Boutique')->searchable()->weight('bold'),
                TextColumn::make('shop.phone')->label('Téléphone du vendeur')->placeholder('—'),
                TextColumn::make('order.reference')->label('Commande'),
                TextColumn::make('goods_total')->label('Articles')->suffix(' FCFA')->numeric(0, ',', ' '),
                TextColumn::make('commission')->label('Commission')->suffix(' FCFA')->numeric(0, ',', ' '),
                TextColumn::make('amount')->label('À reverser')->suffix(' FCFA')->numeric(0, ',', ' ')->weight('bold'),
                TextColumn::make('status')->label('Statut')->badge(),
                TextColumn::make('reference')->label('Référence')->placeholder('—'),
                TextColumn::make('paid_at')->label('Reversé le')->dateTime('d/m H:i')->placeholder('—'),
            ])
            ->filters([
                SelectFilter::make('status')->label('Statut')->options(PayoutStatus::class),
            ])
            ->recordActions([
                Action::make('markPaid')->label('Marquer reversé')->icon(Heroicon::OutlinedCheck)->color('success')
                    ->visible(fn (Payout $record) => $record->status === PayoutStatus::Pending)
                    ->schema([TextInput::make('reference')->label('Référence du transfert')->required()->maxLength(255)])
                    ->action(fn (Payout $record, array $data, ShopPayouts $payouts) => $payouts->markPaid($record, $data['reference'])),
            ]);
    }

    public static function getPages(): array
    {
        return ['index' => ListPayouts::route('/')];
    }
}
