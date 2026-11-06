<?php

namespace App\Filament\Resources\Orders\Pages;

use App\Enums\OrderStatus;
use App\Enums\Role;
use App\Exceptions\WorkflowException;
use App\Filament\Resources\Orders\OrderResource;
use App\Models\Order;
use App\Models\User;
use App\Services\OrderWorkflow;
use Closure;
use Filament\Actions\Action;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\Textarea;
use Filament\Forms\Components\TextInput;
use Filament\Notifications\Notification;
use Filament\Resources\Pages\ViewRecord;

class ViewOrder extends ViewRecord
{
    protected static string $resource = OrderResource::class;

    public function getTitle(): string
    {
        return $this->record->reference;
    }

    protected function getHeaderActions(): array
    {
        return [
            Action::make('setPrice')
                ->label(fn (Order $record) => match (true) {
                    $record->shop_id !== null => 'Fixer les frais de livraison',
                    $record->status === OrderStatus::PricePending => 'Modifier le prix',
                    default => 'Fixer le prix',
                })
                ->icon('heroicon-o-banknotes')
                ->visible(fn (Order $record) => in_array($record->status, [OrderStatus::Received, OrderStatus::PricePending], true))
                ->schema([
                    TextInput::make('price')
                        ->label(fn (Order $record) => $record->shop_id !== null ? 'Frais de livraison en FCFA' : 'Prix en FCFA')
                        ->integer()->minValue(1)->required()
                        ->default(fn (Order $record) => $record->shop_id !== null ? $record->delivery_fee : $record->price),
                ])
                ->action(fn (Order $record, array $data) => $this->run(fn (OrderWorkflow $w) => $w->setPrice($record, (int) $data['price'], auth()->user()), 'Prix envoyé au restaurant')),

            Action::make('assignCourier')
                ->label(fn (Order $record) => $record->courier_id ? 'Changer de livreur' : 'Affecter un livreur')
                ->icon('heroicon-o-user-plus')
                ->visible(fn (Order $record) => in_array($record->status, [OrderStatus::Confirmed, OrderStatus::Preparing], true))
                ->schema([
                    Select::make('courier_id')->label('Livreur')->required()->searchable()
                        ->options(fn () => User::where('role', Role::Courier)->where('is_active', true)->get()
                            ->mapWithKeys(fn (User $u) => [$u->id => $u->name ?? $u->phone])),
                ])
                ->action(fn (Order $record, array $data) => $this->run(fn (OrderWorkflow $w) => $w->assignCourier($record, User::findOrFail($data['courier_id']), auth()->user()), 'Livreur affecté')),

            Action::make('startPreparing')
                ->label('Lancer la préparation')
                ->icon('heroicon-o-archive-box')
                ->requiresConfirmation()
                ->visible(fn (Order $record) => $record->status === OrderStatus::Confirmed)
                ->action(fn (Order $record) => $this->run(fn (OrderWorkflow $w) => $w->startPreparing($record, auth()->user()), 'Commande en préparation')),

            Action::make('startDelivery')
                ->label('Partie en livraison')
                ->icon('heroicon-o-truck')
                ->requiresConfirmation()
                ->visible(fn (Order $record) => $record->status === OrderStatus::Preparing)
                ->action(fn (Order $record) => $this->run(fn (OrderWorkflow $w) => $w->startDelivery($record, auth()->user()), 'Commande en livraison')),

            Action::make('markDelivered')
                ->label('Marquer livrée')
                ->icon('heroicon-o-check-circle')
                ->color('success')
                ->requiresConfirmation()
                ->visible(fn (Order $record) => $record->status === OrderStatus::Delivering)
                ->action(fn (Order $record) => $this->run(fn (OrderWorkflow $w) => $w->markDelivered($record, auth()->user()), 'Commande livrée')),

            Action::make('cancel')
                ->label('Annuler')
                ->icon('heroicon-o-x-circle')
                ->color('danger')
                ->visible(fn (Order $record) => ! $record->status->isFinished())
                ->schema([Textarea::make('reason')->label('Motif')->required()->maxLength(255)])
                ->action(fn (Order $record, array $data) => $this->run(fn (OrderWorkflow $w) => $w->cancel($record, auth()->user(), $data['reason']), 'Commande annulée')),
        ];
    }

    private function run(Closure $step, string $success): void
    {
        try {
            $step(app(OrderWorkflow::class));
            $this->record->refresh();
            Notification::make()->title($success)->success()->send();
        } catch (WorkflowException $e) {
            Notification::make()->title($e->getMessage())->danger()->send();
        }
    }
}
