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

La discussion en direct se branche sur le serveur `reverb:start` de l'ordinateur de l'API, port 8080. Pour un autre port ou une autre adresse :

```bash
flutter run --dart-define=API_URL=http://10.0.2.2:8010/api/v1 --dart-define=REVERB_URL=ws://10.0.2.2:6001
```

## Notifications (Firebase)

Sans réglages Firebase, l'application marche, mais sans notifications. Pour les activer :

1. Sur [console.firebase.google.com](https://console.firebase.google.com), créez un projet, puis ajoutez une application Android et une application iOS avec l'identifiant `com.superlivraison.superlivraison`.
2. Copiez `firebase.example.json` en `firebase.json` et remplissez-le. Les valeurs se trouvent dans les fichiers `google-services.json` (Android) et `GoogleService-Info.plist` (iOS) que la console propose de télécharger :
   - `FIREBASE_PROJECT_ID` : `project_id` / `PROJECT_ID`
   - `FIREBASE_SENDER_ID` : `project_number` / `GCM_SENDER_ID`
   - `FIREBASE_ANDROID_APP_ID` et `FIREBASE_ANDROID_API_KEY` : `mobilesdk_app_id` et `current_key`
   - `FIREBASE_IOS_APP_ID` et `FIREBASE_IOS_API_KEY` : `GOOGLE_APP_ID` et `API_KEY`
3. Lancez l'application avec ces réglages :

```bash
flutter run --dart-define-from-file=firebase.json --dart-define=API_URL=http://10.0.2.2:8010/api/v1
```

Pour l'iPhone, il faut en plus, sur un Mac : dans Xcode, ajouter la capacité « Push Notifications » à la cible Runner, puis déposer une clé APNs (fichier `.p8` du compte Apple Developer) dans Firebase, onglet Cloud Messaging.

`firebase.json` reste en dehors de Git.

En local, le code de connexion se lit dans `backend/storage/logs/laravel.log`.

## Tests

```bash
flutter test
```

## Organisation

- `lib/api` : appels à l'API et messages d'erreur
- `lib/state` : session et file des demandes en attente de réseau
- `lib/screens` : écrans (Livreur, Commandes, Publicités, Boutiques)
- `lib/theme.dart` : couleurs des maquettes, thèmes clair et sombre

Sans réseau, une demande reste sur le téléphone et repart toute seule, avec le même identifiant pour éviter un doublon.
