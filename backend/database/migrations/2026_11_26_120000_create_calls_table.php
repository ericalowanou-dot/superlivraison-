<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('calls', function (Blueprint $table) {
            $table->id();
            $table->foreignId('order_id')->constrained()->cascadeOnDelete();
            $table->foreignId('caller_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('callee_id')->constrained('users')->cascadeOnDelete();
            $table->boolean('video')->default(false);
            $table->string('status', 20);
            $table->timestamp('answered_at')->nullable();
            $table->timestamp('ended_at')->nullable();
            $table->timestamps();

            $table->index(['order_id', 'status']);
        });

        // L'historique de la discussion note chaque appel : « Appel manqué », « Appel vidéo · 2 min ».
        Schema::table('messages', function (Blueprint $table) {
            $table->foreignId('call_id')->nullable()->after('sender_id')->constrained()->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('messages', function (Blueprint $table) {
            $table->dropConstrainedForeignId('call_id');
        });
        Schema::dropIfExists('calls');
    }
};
