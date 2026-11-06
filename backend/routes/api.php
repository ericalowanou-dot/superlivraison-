<?php

use App\Http\Controllers\Api\AdController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\CourierController;
use App\Http\Controllers\Api\MyShopController;
use App\Http\Controllers\Api\OrderController;
use App\Http\Controllers\Api\PaymentController;
use App\Http\Controllers\Api\ProfileController;
use App\Http\Controllers\Api\ReferenceController;
use App\Http\Controllers\Api\ShopController;
use App\Http\Controllers\Api\VoiceNoteController;
use App\Http\Middleware\EnsureAccountIsActive;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {
    Route::get('reference', ReferenceController::class);

    Route::post('auth/request-code', [AuthController::class, 'requestCode'])->middleware('throttle:otp-request');
    Route::post('auth/verify-code', [AuthController::class, 'verifyCode'])->middleware('throttle:otp-verify');

    Route::post('webhooks/payments/{provider}', [PaymentController::class, 'webhook'])->middleware('throttle:120,1');

    Route::middleware(['auth:sanctum', EnsureAccountIsActive::class, 'throttle:api'])->group(function () {
        Route::post('auth/logout', [AuthController::class, 'logout']);

        Route::get('me', [ProfileController::class, 'show']);
        Route::patch('me', [ProfileController::class, 'update']);
        Route::delete('me', [ProfileController::class, 'destroy']);
        Route::post('devices', [ProfileController::class, 'registerDevice']);
        Route::get('notifications', [ProfileController::class, 'notifications']);
        Route::post('notifications/read', [ProfileController::class, 'markNotificationsRead']);

        Route::post('voice-notes', [VoiceNoteController::class, 'store']);
        Route::get('voice-notes/{voiceNote}', [VoiceNoteController::class, 'show']);

        Route::get('orders', [OrderController::class, 'index']);
        Route::post('orders', [OrderController::class, 'store']);
        Route::post('courier-requests', [OrderController::class, 'storeCourierRequest']);
        Route::get('orders/{order}', [OrderController::class, 'show']);
        Route::get('orders/{order}/voice', [OrderController::class, 'voice']);
        Route::post('orders/{order}/accept-price', [OrderController::class, 'acceptPrice']);
        Route::post('orders/{order}/refuse-price', [OrderController::class, 'refusePrice']);
        Route::post('orders/{order}/cancel', [OrderController::class, 'cancel']);
        Route::post('orders/{order}/reorder', [OrderController::class, 'reorder']);
        Route::post('orders/{order}/payments', [PaymentController::class, 'store']);

        Route::get('payments', [PaymentController::class, 'index']);
        Route::get('payments/{payment}', [PaymentController::class, 'show']);
        Route::get('payments/{payment}/receipt', [PaymentController::class, 'receipt']);

        Route::get('ads', [AdController::class, 'index']);
        Route::get('ads/mine', [AdController::class, 'mine']);
        Route::post('ads', [AdController::class, 'store'])->middleware('throttle:10,1');
        Route::delete('ads/{ad}', [AdController::class, 'destroy']);
        Route::get('ads/{ad}/image', [AdController::class, 'image']);

        Route::get('shops', [ShopController::class, 'index']);
        Route::get('shops/{shop}/image', [ShopController::class, 'image']);
        Route::get('shops/{shop}/products', [ShopController::class, 'products']);
        Route::post('shops/{shop}/orders', [ShopController::class, 'checkout'])->middleware('throttle:30,1');
        Route::get('products/{product}/image', [ShopController::class, 'productImage']);

        Route::get('my-shop', [MyShopController::class, 'show']);
        Route::post('my-shop', [MyShopController::class, 'save'])->middleware('throttle:20,1');
        Route::get('my-shop/products', [MyShopController::class, 'products']);
        Route::post('my-shop/products', [MyShopController::class, 'storeProduct'])->middleware('throttle:60,1');
        Route::post('my-shop/products/{product}', [MyShopController::class, 'updateProduct'])->middleware('throttle:60,1');
        Route::delete('my-shop/products/{product}', [MyShopController::class, 'destroyProduct']);
        Route::get('my-shop/orders', [MyShopController::class, 'orders']);
        Route::get('my-shop/payouts', [MyShopController::class, 'payouts']);

        Route::get('courier/deliveries', [CourierController::class, 'index']);
        Route::post('courier/deliveries/{order}/start', [CourierController::class, 'start']);
        Route::post('courier/deliveries/{order}/delivered', [CourierController::class, 'delivered']);
    });
});
