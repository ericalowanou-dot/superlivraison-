<?php

namespace App\Filament\Resources\Payments;

use App\Enums\PaymentStatus;
use App\Exceptions\WorkflowException;
use App\Filament\Resources\Payments\Pages\ListPayments;
use App\Models\Payment;
use App\Services\PaymentService;
use BackedEnum;
use Filament\Actions\Action;
use Filament\Notifications\Notification;
use Filament\Resources\Resource;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\IconColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\Filter;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Support\Facades\Gate;

class PaymentResource extends Resource
{
    protected static ?string $model = Payment::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedCreditCard;

    protected static ?string $navigationLabel = 'Paiements';

    protected static ?string $modelLabel = 'paiement';

    protected static ?string $pluralModelLabel = 'paiements';

    protected static ?int $navigationSort = 2;

    public static function getNavigationBadge(): ?string
    {
        $count = Payment::where('needs_review', true)->count();

        return $count > 0 ? (string) $count : null;
    }

    public static function getNavigationBadgeColor(): ?string
    {
        return 'danger';
    }

    public static function table(Table $table): Table
    {
        return $table
            ->defaultSort('id', 'desc')
            ->modifyQueryUsing(fn ($query) => $query->with(['order', 'user']))
            ->columns([
                TextColumn::make('order.reference')->label('Commande')->searchable(),
                TextColumn::make('user.business_name')->label('Restaurant')->placeholder('—'),
                TextColumn::make('method')->label('Moyen'),
                TextColumn::make('amount')->label('Montant')->suffix(' FCFA')->numeric(0, ',', ' '),
                TextColumn::make('status')->label('Statut')->badge(),
                IconColumn::make('needs_review')->label('À vérifier')->boolean()
                    ->trueColor('danger')->falseColor('gray')->trueIcon('heroicon-o-exclamation-triangle')->falseIcon('heroicon-o-minus'),
                TextColumn::make('failure_reason')->label('Détail')->placeholder('—')->limit(40),
                TextColumn::make('paid_at')->label('Payé le')->dateTime('d/m/Y H:i')->placeholder('—'),
            ])
            ->filters([
                SelectFilter::make('status')->label('Statut')->options(PaymentStatus::class),
                Filter::make('needs_review')->label('À vérifier')->query(fn ($query) => $query->where('needs_review', true)),
            ])
            ->recordActions([
                Action::make('refund')
                    ->label('Rembourser')
                    ->icon('heroicon-o-arrow-uturn-left')
                    ->color('danger')
                    ->requiresConfirmation()
                    ->modalDescription(fn (Payment $record) => "Rembourser {$record->amount} FCFA ?")
                    ->visible(fn (Payment $record) => $record->status === PaymentStatus::Succeeded && Gate::allows('refund', $record))
                    ->action(function (Payment $record) {
                        Gate::authorize('refund', $record);

                        try {
                            app(PaymentService::class)->refund($record, auth()->user());
                            Notification::make()->title('Paiement remboursé')->success()->send();
                        } catch (WorkflowException $e) {
                            Notification::make()->title($e->getMessage())->danger()->send();
                        }
                    }),
            ]);
    }

    public static function getPages(): array
    {
        return ['index' => ListPayments::route('/')];
    }
}
