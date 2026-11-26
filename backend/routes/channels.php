<?php

use App\Models\Order;
use App\Models\User;
use Illuminate\Support\Facades\Broadcast;

// La discussion d'une course : le client et le livreur affecté, et l'équipe pour le suivi.
Broadcast::channel('orders.{order}', fn (User $user, Order $order) => $user->can('view', $order));
