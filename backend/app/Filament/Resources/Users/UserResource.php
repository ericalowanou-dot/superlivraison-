<?php

namespace App\Filament\Resources\Users;

use App\Enums\Role;
use App\Filament\Resources\Users\Pages\CreateUser;
use App\Filament\Resources\Users\Pages\EditUser;
use App\Filament\Resources\Users\Pages\ListUsers;
use App\Models\User;
use BackedEnum;
use Filament\Actions\EditAction;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Toggle;
use Filament\Resources\Resource;
use Filament\Schemas\Components\Utilities\Get;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\IconColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Validation\Rules\Password;

class UserResource extends Resource
{
    protected static ?string $model = User::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedUsers;

    protected static ?string $navigationLabel = 'Utilisateurs';

    protected static ?string $modelLabel = 'utilisateur';

    protected static ?string $pluralModelLabel = 'utilisateurs';

    protected static ?int $navigationSort = 3;

    public static function canAccess(): bool
    {
        return auth()->user()?->isAdmin() ?? false;
    }

    public static function form(Schema $schema): Schema
    {
        $isStaff = fn (Get $get) => ($r = $get('role')) instanceof Role ? $r->isStaff() : Role::tryFrom((string) $r)?->isStaff();
        $self = fn (?User $record) => $record?->id === auth()->id();

        return $schema->components([
            Select::make('role')->label('Rôle')->options(Role::class)->required()->live()
                ->default(Role::Courier)->disabled($self)->dehydrated(fn (?User $record) => $record?->id !== auth()->id()),
            TextInput::make('name')->label('Nom')->maxLength(120),
            TextInput::make('business_name')->label('Nom du commerce')->maxLength(120),
            TextInput::make('phone')->label('Téléphone')->tel()->placeholder('+22890000000')
                ->regex('/^\+[1-9]\d{7,14}$/')->unique(ignoreRecord: true)
                ->required(fn (Get $get) => ! $isStaff($get)),
            TextInput::make('email')->label('E-mail')->email()->unique(ignoreRecord: true)
                ->required($isStaff),
            TextInput::make('password')->label('Mot de passe')->password()->revealable()
                ->rule(Password::min(12))
                ->required(fn (string $operation, Get $get) => $operation === 'create' && $isStaff($get))
                ->dehydrated(fn (?string $state) => filled($state))
                ->helperText('Laisser vide pour ne pas le changer.'),
            Select::make('city_id')->label('Ville')->relationship('city', 'name')->preload(),
            Toggle::make('is_active')->label('Compte actif')->default(true)->disabled($self)
                ->dehydrated(fn (?User $record) => $record?->id !== auth()->id()),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->defaultSort('id', 'desc')
            ->columns([
                TextColumn::make('name')->label('Nom')->searchable()->placeholder('—'),
                TextColumn::make('business_name')->label('Commerce')->searchable()->placeholder('—'),
                TextColumn::make('phone')->label('Téléphone')->searchable()->placeholder('—'),
                TextColumn::make('email')->label('E-mail')->searchable()->placeholder('—'),
                TextColumn::make('role')->label('Rôle')->badge(),
                TextColumn::make('city.name')->label('Ville')->placeholder('—'),
                IconColumn::make('is_active')->label('Actif')->boolean(),
            ])
            ->filters([SelectFilter::make('role')->label('Rôle')->options(Role::class)])
            ->recordActions([EditAction::make()]);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListUsers::route('/'),
            'create' => CreateUser::route('/create'),
            'edit' => EditUser::route('/{record}/edit'),
        ];
    }
}
