<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('shops', function (Blueprint $table) {
            $table->foreignId('owner_id')->nullable()->unique()->after('id')->constrained('users')->nullOnDelete();
            $table->string('status', 20)->default('pending')->index()->after('is_active');
            $table->string('rejection_reason')->nullable()->after('status');
            $table->timestamp('approved_at')->nullable()->after('rejection_reason');
        });

        // Les boutiques déjà saisies par l'équipe restent visibles.
        DB::table('shops')->update(['status' => 'approved', 'approved_at' => now()]);

        Schema::create('products', function (Blueprint $table) {
            $table->id();
            $table->foreignId('shop_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->text('description')->nullable();
            $table->unsignedBigInteger('price');
            $table->unsignedInteger('stock')->nullable();
            $table->string('image_path');
            $table->boolean('is_active')->default(true)->index();
            $table->timestamps();
        });

        Schema::table('orders', function (Blueprint $table) {
            $table->foreignId('shop_id')->nullable()->after('city_id')->constrained()->nullOnDelete();
            $table->unsignedBigInteger('goods_total')->nullable()->after('price');
            $table->unsignedBigInteger('delivery_fee')->nullable()->after('goods_total');
        });

        Schema::create('order_items', function (Blueprint $table) {
            $table->id();
            $table->foreignId('order_id')->constrained()->cascadeOnDelete();
            $table->foreignId('product_id')->nullable()->constrained()->nullOnDelete();
            $table->string('name');
            $table->unsignedBigInteger('unit_price');
            $table->unsignedInteger('quantity');
            $table->timestamps();
        });

        Schema::create('payouts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('shop_id')->constrained()->restrictOnDelete();
            $table->foreignId('order_id')->unique()->constrained()->restrictOnDelete();
            $table->unsignedBigInteger('goods_total');
            $table->unsignedBigInteger('commission');
            $table->unsignedBigInteger('amount');
            $table->string('status', 20)->default('pending')->index();
            $table->string('reference')->nullable();
            $table->timestamp('paid_at')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('payouts');
        Schema::dropIfExists('order_items');

        Schema::table('orders', function (Blueprint $table) {
            $table->dropConstrainedForeignId('shop_id');
            $table->dropColumn(['goods_total', 'delivery_fee']);
        });

        Schema::dropIfExists('products');

        Schema::table('shops', function (Blueprint $table) {
            $table->dropConstrainedForeignId('owner_id');
            $table->dropColumn(['status', 'rejection_reason', 'approved_at']);
        });
    }
};
