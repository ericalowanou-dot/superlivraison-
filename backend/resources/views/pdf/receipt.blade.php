<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<style>
body{font-family:DejaVu Sans,sans-serif;font-size:13px;color:#0B2F44}
h1{font-size:22px;color:#0B7FAB;margin:0 0 4px}
table{width:100%;border-collapse:collapse;margin-top:20px}
td{padding:9px 6px;border-bottom:1px solid #BFE3F2}
td:first-child{color:#4A6B7C;width:40%}
.total{font-size:18px;font-weight:bold}
</style>
</head>
<body>
<h1>Reçu de paiement</h1>
<div>{{ config('app.name') }}</div>
<table>
<tr><td>Commande</td><td>{{ $payment->order->reference }}</td></tr>
<tr><td>Client</td><td>{{ $payment->user->business_name ?? $payment->user->name ?? $payment->user->phone }}</td></tr>
<tr><td>Date</td><td>{{ $payment->paid_at?->format('d/m/Y H:i') }}</td></tr>
<tr><td>Moyen de paiement</td><td>{{ $payment->method->getLabel() }}</td></tr>
<tr><td>Statut</td><td>{{ $payment->status->getLabel() }}</td></tr>
<tr><td>Référence</td><td>{{ $payment->reference }}</td></tr>
<tr><td>Montant</td><td class="total">{{ number_format($payment->amount, 0, ',', ' ') }} {{ $payment->currency === 'XOF' ? 'FCFA' : $payment->currency }}</td></tr>
</table>
</body>
</html>
