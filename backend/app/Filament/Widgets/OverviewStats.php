<?php

namespace App\Filament\Widgets;

use App\Enums\OrderStatus;
use App\Enums\PaymentStatus;
use App\Models\Order;
use App\Models\Payment;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class OverviewStats extends StatsOverviewWidget
{
    protected ?string $pollingInterval = '30s';

    protected function getStats(): array
    {
        $today = now()->startOfDay();
        $cashed = Payment::where('status', PaymentStatus::Succeeded)->where('paid_at', '>=', $today)->sum('amount');

        return [
            Stat::make('Demandes à chiffrer', Order::where('status', OrderStatus::Received)->count()),
            Stat::make('Commandes du jour', Order::where('created_at', '>=', $today)->count()),
            Stat::make('En livraison', Order::where('status', OrderStatus::Delivering)->count()),
            Stat::make('Encaissé aujourd\'hui', number_format((float) $cashed, 0, ',', ' ').' FCFA'),
            Stat::make('Paiements à vérifier', Payment::where('needs_review', true)->count()),
        ];
    }
}
