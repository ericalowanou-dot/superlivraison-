<?php

namespace App\Filament\Resources\Orders\Schemas;

use App\Models\Order;
use Filament\Infolists\Components\IconEntry;
use Filament\Infolists\Components\RepeatableEntry;
use Filament\Infolists\Components\TextEntry;
use Filament\Infolists\Components\ViewEntry;
use Filament\Schemas\Components\Grid;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Schema;

class OrderInfolist
{
    public static function configure(Schema $schema): Schema
    {
        return $schema->columns(3)->components([
            Grid::make(1)->columnSpan(2)->schema([
                Section::make('Demande')->schema([
                    TextEntry::make('request_text')->label('Texte')->columnSpanFull(),
                    ViewEntry::make('voice')->label('Vocal')->view('filament.voice-player')
                        ->visible(fn (Order $record) => $record->voice_note_id !== null),
                ]),
                Section::make('Articles')->visible(fn (Order $record) => $record->shop_id !== null)->schema([
                    TextEntry::make('shop.name')->label('Boutique'),
                    TextEntry::make('shop.phone')->label('Téléphone de la boutique')->placeholder('Non renseigné'),
                    TextEntry::make('shop.landmark')->label('Lieu de retrait')->placeholder('Non renseigné'),
                    RepeatableEntry::make('items')->hiddenLabel()->columns(3)->schema([
                        TextEntry::make('name')->label('Article'),
                        TextEntry::make('quantity')->label('Quantité'),
                        TextEntry::make('unit_price')->label('Prix unitaire')->suffix(' FCFA')->numeric(0, ',', ' '),
                    ]),
                    TextEntry::make('goods_total')->label('Total des articles')->suffix(' FCFA')->numeric(0, ',', ' '),
                    TextEntry::make('delivery_fee')->label('Frais de livraison')->suffix(' FCFA')->numeric(0, ',', ' ')->placeholder('À fixer'),
                ]),
                Section::make('Livraison')->columns(2)->schema([
                    TextEntry::make('recipient_phone')->label('Téléphone du destinataire')
                        ->visible(fn (Order $record) => $record->recipient_phone !== null),
                    TextEntry::make('delivery_landmark')->label('Repère'),
                    TextEntry::make('map')->label('Position')
                        ->state(fn (Order $record) => $record->delivery_lat === null ? 'Non indiquée' : 'Voir sur la carte')
                        ->url(fn (Order $record) => $record->delivery_lat === null ? null : "https://www.openstreetmap.org/?mlat={$record->delivery_lat}&mlon={$record->delivery_lng}#map=18/{$record->delivery_lat}/{$record->delivery_lng}", true),
                    TextEntry::make('courier.name')->label('Livreur')->placeholder('Non affecté'),
                ]),
                Section::make('Paiements')->schema([
                    RepeatableEntry::make('payments')->hiddenLabel()->columns(4)->placeholder('Aucun paiement')->schema([
                        TextEntry::make('method')->label('Moyen'),
                        TextEntry::make('amount')->label('Montant')->suffix(' FCFA')->numeric(0, ',', ' '),
                        TextEntry::make('status')->label('Statut')->badge(),
                        IconEntry::make('needs_review')->label('À vérifier')->boolean(),
                    ]),
                ]),
            ]),
            Grid::make(1)->columnSpan(1)->schema([
                Section::make('Résumé')->schema([
                    TextEntry::make('reference')->label('Référence'),
                    TextEntry::make('status')->label('Statut')->badge(),
                    TextEntry::make('restaurant_label')->label('Restaurant')
                        ->state(fn (Order $record) => $record->restaurant->business_name ?? $record->restaurant->name ?? 'Compte supprimé'),
                    TextEntry::make('restaurant.phone')->label('Téléphone')->placeholder('Non renseigné'),
                    TextEntry::make('city.name')->label('Ville'),
                    TextEntry::make('channel')->label('Canal'),
                    TextEntry::make('price')->label('Prix')->suffix(' FCFA')->numeric(0, ',', ' ')->placeholder('À fixer'),
                    TextEntry::make('payment_mode')->label('Mode de paiement')->placeholder('Non choisi'),
                    IconEntry::make('paid')->label('Payée')->boolean()->state(fn (Order $record) => $record->isPaid()),
                    TextEntry::make('refusal_reason')->label('Motif du refus')->placeholder('Aucun')
                        ->visible(fn (Order $record) => $record->refusal_reason !== null),
                    TextEntry::make('cancel_reason')->label('Motif d\'annulation')
                        ->visible(fn (Order $record) => $record->cancel_reason !== null),
                ]),
                Section::make('Historique')->schema([
                    RepeatableEntry::make('events')->hiddenLabel()->schema([
                        TextEntry::make('to_status')->hiddenLabel()->badge(),
                        TextEntry::make('note')->hiddenLabel()->placeholder(''),
                        TextEntry::make('created_at')->hiddenLabel()->dateTime('d/m/Y H:i')->color('gray'),
                    ]),
                ]),
            ]),
        ]);
    }
}
