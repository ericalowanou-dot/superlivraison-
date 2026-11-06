<?php

namespace App\Filament\Resources\Ads;

use App\Enums\AdCategory;
use App\Enums\ReviewStatus;
use App\Filament\Resources\Ads\Pages\ManageAds;
use App\Models\Ad;
use App\Services\AdModeration;
use BackedEnum;
use Filament\Actions\Action;
use Filament\Actions\DeleteAction;
use Filament\Forms\Components\FileUpload;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\Textarea;
use Filament\Forms\Components\TextInput;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\ImageColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;

class AdResource extends Resource
{
    protected static ?string $model = Ad::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedMegaphone;

    protected static ?string $navigationLabel = 'Publicités';

    protected static ?string $modelLabel = 'publicité';

    protected static ?string $pluralModelLabel = 'publicités';

    public static function getNavigationBadge(): ?string
    {
        $pending = Ad::where('status', ReviewStatus::Pending)->count();

        return $pending > 0 ? (string) $pending : null;
    }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Select::make('city_id')->label('Ville')->relationship('city', 'name')->required()->preload(),
            Select::make('category')->label('Type')->options(AdCategory::class)->required(),
            TextInput::make('title')->label('Titre')->required()->minLength(3)->maxLength(120),
            Textarea::make('description')->label('Description')->maxLength(2000),
            FileUpload::make('image_path')->label('Affiche')->image()->required()
                ->disk(fn () => config('superlivraison.media_disk'))->directory('ads/admin')->visibility('private')
                ->maxSize(config('superlivraison.ad_image_max_kb')),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->defaultSort('id', 'desc')
            ->modifyQueryUsing(fn ($query) => $query->with(['user', 'city']))
            ->columns([
                ImageColumn::make('image_path')->label('Affiche')
                    ->disk(fn () => config('superlivraison.media_disk'))->visibility('private'),
                TextColumn::make('title')->label('Titre')->searchable()->weight('bold'),
                TextColumn::make('category')->label('Type'),
                TextColumn::make('author')->label('Auteur')
                    ->state(fn (Ad $record) => $record->user?->business_name ?? $record->user?->name ?? $record->user?->phone ?? 'Compte supprimé'),
                TextColumn::make('city.name')->label('Ville'),
                TextColumn::make('status')->label('Statut')->badge(),
                TextColumn::make('created_at')->label('Envoyée le')->dateTime('d/m H:i')->sortable(),
            ])
            ->filters([
                SelectFilter::make('status')->label('Statut')->options(ReviewStatus::class),
            ])
            ->recordActions([
                Action::make('approve')->label('Publier')->icon(Heroicon::OutlinedCheck)->color('success')
                    ->visible(fn (Ad $record) => $record->status !== ReviewStatus::Approved)
                    ->requiresConfirmation()
                    ->action(fn (Ad $record, AdModeration $moderation) => $moderation->approve($record)),
                Action::make('reject')->label('Refuser')->icon(Heroicon::OutlinedXMark)->color('danger')
                    ->visible(fn (Ad $record) => $record->status !== ReviewStatus::Rejected)
                    ->schema([Textarea::make('reason')->label('Motif')->required()->maxLength(255)])
                    ->action(fn (Ad $record, array $data, AdModeration $moderation) => $moderation->reject($record, $data['reason'])),
                DeleteAction::make(),
            ]);
    }

    public static function getPages(): array
    {
        return ['index' => ManageAds::route('/')];
    }
}
