# Backend de l'application de livraison

API de l'application mobile et administration web, avec Laravel, Filament et PostgreSQL.

- API : `/api/v1`
- Administration : `/admin`

## Lancer en local

```bash
composer install
copy .env.example .env
php artisan key:generate
php artisan migrate --seed
php artisan serve
php artisan queue:work
```

Renseignez `ADMIN_EMAIL` et `ADMIN_PASSWORD` dans `.env` avant `migrate --seed` pour créer le premier administrateur.

`queue:work` envoie les notifications et lance les retranscriptions.

## Tests

```bash
php artisan test
```

## Base de données

Le fichier `.env` utilise SQLite par défaut. La production utilise PostgreSQL :

```
DB_CONNECTION=pgsql
DB_HOST=127.0.0.1
DB_PORT=5432
DB_DATABASE=superlivraison
DB_USERNAME=superlivraison
DB_PASSWORD=
```

## Services externes

Chaque service passe par une interface de `app/Contracts`. Les versions de simulation écrivent dans le journal et l'application refuse de démarrer avec elles en production.

| Service | Variable | Interface |
|---|---|---|
| SMS de connexion | `SMS_DRIVER` | `SmsSender` |
| Notifications | `PUSH_DRIVER` | `PushSender` |
| Retranscription | `TRANSCRIBER_DRIVER` | `Transcriber` |
| Paiement mobile | `PAYMENT_DRIVER` | `PaymentGateway` |

En local, le code de connexion se lit dans `storage/logs/laravel.log`.

## Règles métier

Les étapes d'une commande passent par `app/Services/OrderWorkflow.php` et les paiements par `app/Services/PaymentService.php`.

- Seul un webhook signé confirme un paiement mobile.
- Une commande en paiement mobile n'entre en préparation qu'une fois payée.
- Un paiement au montant incorrect, en double ou reçu après une annulation passe « à vérifier » dans l'administration.
- La confirmation de livraison vaut encaissement pour un paiement en espèces.
