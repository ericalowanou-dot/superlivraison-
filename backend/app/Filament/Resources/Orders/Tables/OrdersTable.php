<?php

namespace App\Filament\Resources\Orders\Tables;

use App\Enums\OrderStatus;
use App\Models\Order;
use Filament\Actions\ViewAction;
use Filament\Tables\Columns\IconColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;

class OrdersTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->defaultSort('id', 'desc')
            ->poll('15s')
            ->modifyQueryUsing(fn ($query) => $query->with(['restaurant', 'city']))
            ->columns([
                TextColumn::make('reference')->label('Commande')->searchable()->weight('bold'),
                TextColumn::make('restaurant_label')->label('Restaurant')
                    ->state(fn (Order $record) => $record->restaurant->business_name ?? $record->restaurant->name ?? $record->restaurant->phone ?? 'Compte supprimé'),
                TextColumn::make('city.name')->label('Ville'),
                TextColumn::make('channel')->label('Canal'),
                TextColumn::make('status')->label('Statut')->badge(),
                TextColumn::make('price')->label('Prix')->suffix(' FCFA')->numeric(0, ',', ' ')->placeholder('—'),
                IconColumn::make('paid')->label('Payée')->boolean()->state(fn (Order $record) => $record->isPaid()),
                TextColumn::make('created_at')->label('Reçue le')->dateTime('d/m H:i')->sortable(),
            ])
            ->filters([
                SelectFilter::make('status')->label('Statut')->options(OrderStatus::class),
            ])
            ->recordActions([ViewAction::make()]);
    }
}
