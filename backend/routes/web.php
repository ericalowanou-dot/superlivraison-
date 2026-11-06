<?php

use App\Models\Order;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\Storage;

Route::redirect('/', '/admin');

// Écoute du vocal depuis l'administration : le fichier reste privé.
Route::get('/admin-media/orders/{order}/voice', function (Order $order) {
    Gate::authorize('update', $order);
    abort_unless($order->voiceNote, 404);

    return Storage::disk(config('superlivraison.media_disk'))->response($order->voiceNote->path);
})->middleware('auth')->name('staff.orders.voice');
