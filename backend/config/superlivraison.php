<?php

return [
    /*
     * Chaque service externe reste remplaçable. Les valeurs « log » et « fake »
     * ne servent qu'au développement : l'application refuse de démarrer avec elles en production.
     */
    'sms_driver' => env('SMS_DRIVER', 'log'),
    'push_driver' => env('PUSH_DRIVER', 'log'),
    'transcriber_driver' => env('TRANSCRIBER_DRIVER', 'fake'),
    'payment_driver' => env('PAYMENT_DRIVER', 'fake'),
    'fake_payment_secret' => env('FAKE_PAYMENT_SECRET', 'dev-secret'),

    'otp' => [
        'length' => 6,
        'ttl_minutes' => 5,
        'max_attempts' => 5,
    ],

    // Une demande sans réponse depuis ce délai n'empêche plus une nouvelle tentative.
    'payment_pending_minutes' => 15,

    'media_disk' => env('MEDIA_DISK', 'local'),

    'ad_image_max_kb' => 5120,

    'shop_commission_percent' => (int) env('SHOP_COMMISSION_PERCENT', 10),
    'voice_max_kb' => 15360,
];
