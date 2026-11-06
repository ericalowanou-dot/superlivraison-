# Application mobile

Application Flutter pour Android et iOS. Elle utilise l'API du dossier `backend`.

## Lancer en local

Le serveur local doit tourner, sur le port 8010 si le port 8000 est déjà pris :

```bash
php artisan serve --port=8010
```

Sur un émulateur Android, l'adresse `10.0.2.2` désigne votre ordinateur :

```bash
flutter run --dart-define=API_URL=http://10.0.2.2:8010/api/v1
```

Sur un téléphone branché, remplacez-la par l'adresse de l'ordinateur sur le réseau local, et lancez le serveur avec `--host=0.0.0.0`.

Dans un navigateur :

```bash
flutter run -d chrome --dart-define=API_URL=http://localhost:8010/api/v1
```

En local, le code de connexion se lit dans `backend/storage/logs/laravel.log`.

## Tests

```bash
flutter test
```

## Organisation

- `lib/api` : appels à l'API et messages d'erreur
- `lib/state` : session et file des demandes en attente de réseau
- `lib/screens` : écrans
- `lib/theme.dart` : couleurs des maquettes, thèmes clair et sombre

Sans réseau, une demande reste sur le téléphone et repart toute seule, avec le même identifiant pour éviter un doublon.
