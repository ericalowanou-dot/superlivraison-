<?php

namespace App\Filament\Resources\Shops;

use App\Filament\Resources\Shops\Pages\ManageShops;
use App\Models\Shop;
use BackedEnum;
use Filament\Actions\DeleteAction;
use Filament\Actions\EditAction;
use Filament\Forms\Components\FileUpload;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\Textarea;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Toggle;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\IconColumn;
use Filament\Tables\Columns\ImageColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;

class ShopResource extends Resource
{
    protected static ?string $model = Shop::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedBuildingStorefront;

    protected static ?string $navigationLabel = 'Boutiques';

    protected static ?string $modelLabel = 'boutique';

    protected static ?string $pluralModelLabel = 'boutiques';

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Select::make('city_id')->label('Ville')->relationship('city', 'name')->required()->preload(),
            TextInput::make('name')->label('Nom')->required()->maxLength(255),
            TextInput::make('category')->label('Activité')->maxLength(100),
            TextInput::make('phone')->label('Téléphone')->tel()->maxLength(20),
            TextInput::make('landmark')->label('Adresse ou repère')->maxLength(255),
            TextInput::make('lat')->label('Latitude')->numeric()->minValue(-90)->maxValue(90),
            TextInput::make('lng')->label('Longitude')->numeric()->minValue(-180)->maxValue(180),
            Textarea::make('description')->label('Description')->maxLength(2000),
            FileUpload::make('image_path')->label('Photo')->image()
                ->disk(fn () => config('superlivraison.media_disk'))->directory('shops')->visibility('private')
                ->maxSize(config('superlivraison.ad_image_max_kb')),
            Toggle::make('is_active')->label('Visible dans l\'application')->default(true),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->defaultSort('name')
            ->modifyQueryUsing(fn ($query) => $query->with('city'))
            ->columns([
                ImageColumn::make('image_path')->label('Photo')
                    ->disk(fn () => config('superlivraison.media_disk'))->visibility('private'),
                TextColumn::make('name')->label('Nom')->searchable()->weight('bold'),
                TextColumn::make('category')->label('Activité')->placeholder('—'),
                TextColumn::make('city.name')->label('Ville'),
                TextColumn::make('phone')->label('Téléphone')->placeholder('—'),
                IconColumn::make('is_active')->label('Visible')->boolean(),
            ])
            ->recordActions([EditAction::make(), DeleteAction::make()]);
    }

    public static function getPages(): array
    {
        return ['index' => ManageShops::route('/')];
    }
}
