<?php

namespace App\Filament\Resources\Products;

use App\Filament\Resources\Products\Pages\ListProducts;
use App\Models\Product;
use BackedEnum;
use Filament\Actions\DeleteAction;
use Filament\Resources\Resource;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\ImageColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Columns\ToggleColumn;
use Filament\Tables\Table;

/** L'équipe contrôle les articles des vendeurs et peut en retirer de la vente. */
class ProductResource extends Resource
{
    protected static ?string $model = Product::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedShoppingBag;

    protected static ?string $navigationLabel = 'Articles';

    protected static ?string $modelLabel = 'article';

    protected static ?string $pluralModelLabel = 'articles';

    public static function canCreate(): bool
    {
        return false;
    }

    public static function table(Table $table): Table
    {
        return $table
            ->defaultSort('id', 'desc')
            ->modifyQueryUsing(fn ($query) => $query->with('shop'))
            ->columns([
                ImageColumn::make('image_path')->label('Photo')
                    ->disk(fn () => config('superlivraison.media_disk'))->visibility('private'),
                TextColumn::make('name')->label('Nom')->searchable()->weight('bold'),
                TextColumn::make('shop.name')->label('Boutique')->searchable(),
                TextColumn::make('price')->label('Prix')->suffix(' FCFA')->numeric(0, ',', ' '),
                TextColumn::make('stock')->label('Stock')->placeholder('Illimité'),
                ToggleColumn::make('is_active')->label('En vente'),
            ])
            ->recordActions([DeleteAction::make()]);
    }

    public static function getPages(): array
    {
        return ['index' => ListProducts::route('/')];
    }
}
