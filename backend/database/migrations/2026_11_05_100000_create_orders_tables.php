<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('voice_notes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('path');
            $table->unsignedInteger('duration_seconds')->nullable();
            $table->string('status', 20)->default('processing');
            $table->text('transcript')->nullable();
            $table->timestamps();
        });

        Schema::create('orders', function (Blueprint $table) {
            $table->id();
            $table->string('reference', 20)->nullable()->unique();
            // Évite un doublon quand le téléphone renvoie après une coupure de réseau.
            $table->uuid('client_uuid');
            $table->foreignId('restaurant_id')->constrained('users')->restrictOnDelete();
            $table->foreignId('city_id')->constrained()->restrictOnDelete();
            $table->foreignId('courier_id')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('voice_note_id')->nullable()->constrained()->nullOnDelete();
            $table->string('channel', 10);
            $table->text('request_text');
            $table->decimal('delivery_lat', 10, 7)->nullable();
            $table->decimal('delivery_lng', 10, 7)->nullable();
            $table->string('delivery_landmark');
            $table->string('status', 20)->default('received')->index();
            $table->unsignedBigInteger('price')->nullable();
            $table->char('currency', 3)->default('XOF');
            $table->string('payment_mode', 20)->nullable();
            $table->string('refusal_reason')->nullable();
            $table->string('cancel_reason')->nullable();
            $table->timestamp('priced_at')->nullable();
            $table->timestamp('confirmed_at')->nullable();
            $table->timestamp('paid_at')->nullable();
            $table->timestamp('delivered_at')->nullable();
            $table->timestamps();
            $table->unique(['restaurant_id', 'client_uuid']);
        });

        Schema::create('order_events', function (Blueprint $table) {
            $table->id();
            $table->foreignId('order_id')->constrained()->cascadeOnDelete();
            $table->foreignId('actor_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('from_status', 20)->nullable();
            $table->string('to_status', 20);
            $table->string('note')->nullable();
            $table->timestamp('created_at')->useCurrent();
        });

        Schema::create('payments', function (Blueprint $table) {
            $table->id();
            $table->uuid('reference')->unique();
            $table->foreignId('order_id')->constrained()->restrictOnDelete();
            $table->foreignId('user_id')->constrained()->restrictOnDelete();
            $table->unsignedBigInteger('amount');
            $table->char('currency', 3)->default('XOF');
            $table->string('method', 10);
            $table->string('status', 20)->default('pending')->index();
            $table->string('provider', 30)->nullable();
            $table->string('provider_reference')->nullable();
            $table->string('payer_phone', 20)->nullable();
            $table->string('failure_reason')->nullable();
            // Paiement à vérifier par l'équipe : montant différent ou commande déjà payée.
            $table->boolean('needs_review')->default(false);
            $table->timestamp('paid_at')->nullable();
            $table->timestamp('refunded_at')->nullable();
            $table->foreignId('refunded_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
            $table->unique(['provider', 'provider_reference']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('payments');
        Schema::dropIfExists('order_events');
        Schema::dropIfExists('orders');
        Schema::dropIfExists('voice_notes');
    }
};
