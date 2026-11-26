import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import 'calls.dart';

/// Ce que contient une notification : de quoi ouvrir le bon écran.
class PushTarget {
  PushTarget.fromData(Map<String, dynamic> data, {this.title, this.body})
      : kind = data['kind'] as String? ?? 'order',
        orderId = int.tryParse('${data['order_id'] ?? ''}'),
        reference = data['reference'] as String?;

  final String kind;
  final int? orderId;
  final String? reference, title, body;

  bool get isMessage => kind == 'message';
}

/// Message silencieux reçu appli fermée : faire sonner un appel, ou arrêter la sonnerie.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  final kind = message.data['kind'];
  if (kind != 'call' && kind != 'call_ended') return;

  final options = Push.options;
  if (options != null && Firebase.apps.isEmpty) await Firebase.initializeApp(options: options);

  if (kind == 'call') {
    await showIncomingCall(message.data);
  } else {
    final callId = int.tryParse('${message.data['call_id']}');
    if (callId != null) await stopRinging(callId);
  }
}

/// Notifications du téléphone par Firebase Cloud Messaging.
///
/// Les réglages du projet Firebase arrivent par `--dart-define-from-file=firebase.json`.
/// Sans eux, l'application tourne normalement, simplement sans notifications.
class Push {
  Push(this.api);

  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const _androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const _androidApiKey = String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
  static const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const _iosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY');
  static const _iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');

  final ApiClient api;

  /// Notification reçue appli ouverte : l'écran décide comment la montrer.
  void Function(PushTarget target)? onForeground;

  /// Notification touchée par l'utilisateur : ouvrir l'écran concerné.
  void Function(PushTarget target)? onOpen;

  /// Message silencieux reçu appli ouverte (appel qui sonne, appel annulé).
  void Function(Map<String, dynamic> data)? onData;

  bool _ready = false;
  String? _token;
  PushTarget? _pendingOpen;
  StreamSubscription<String>? _refresh;

  /// Le jeton de ce téléphone, envoyé à la déconnexion pour couper ses notifications.
  String? get token => _token;

  static FirebaseOptions? get options {
    if (kIsWeb || _projectId.isEmpty || _senderId.isEmpty) return null;

    return switch (defaultTargetPlatform) {
      TargetPlatform.android when _androidAppId.isNotEmpty && _androidApiKey.isNotEmpty => const FirebaseOptions(
          apiKey: _androidApiKey,
          appId: _androidAppId,
          messagingSenderId: _senderId,
          projectId: _projectId,
        ),
      TargetPlatform.iOS when _iosAppId.isNotEmpty && _iosApiKey.isNotEmpty => const FirebaseOptions(
          apiKey: _iosApiKey,
          appId: _iosAppId,
          messagingSenderId: _senderId,
          projectId: _projectId,
          iosBundleId: _iosBundleId,
        ),
      _ => null,
    };
  }

  Future<void> init() async {
    final options = Push.options;
    if (options == null) return;

    try {
      await Firebase.initializeApp(options: options);
      _ready = true;

      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
      FirebaseMessaging.onMessage.listen((m) {
        if (m.notification == null) {
          onData?.call(m.data);
        } else {
          onForeground?.call(_target(m));
        }
      });
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(_target(m)));

      // L'application a été lancée en touchant une notification.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _pendingOpen = _target(initial);
    } catch (e) {
      debugPrint('Notifications indisponibles : $e');
    }
  }

  /// Ouvre l'écran d'une notification touchée avant que l'interface soit prête.
  void openPending() {
    final pending = _pendingOpen;
    _pendingOpen = null;
    if (pending != null) _open(pending);
  }

  /// Demande l'autorisation et donne le jeton du téléphone au serveur. À appeler une fois connecté.
  Future<void> register() async {
    if (!_ready || api.token == null) return;

    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      // Sur iPhone, le jeton Firebase n'existe qu'après celui d'Apple.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        for (var i = 0; i < 10 && await messaging.getAPNSToken() == null; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }

      // Le serveur envoie au jeton d'enregistrement (champ « token » de l'API HTTP v1).
      // L'identifiant d'installation qui le remplace n'est pas encore utilisé côté serveur.
      // ignore: deprecated_member_use
      final token = await messaging.getToken();
      if (token != null) await _send(token);

      // ignore: deprecated_member_use
      _refresh ??= messaging.onTokenRefresh.listen(_send);
    } catch (e) {
      debugPrint('Enregistrement des notifications impossible : $e');
    }
  }

  Future<void> _send(String token) async {
    _token = token;
    if (api.token == null) return;

    try {
      await api.post('/devices', {
        'token': token,
        'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      });
    } catch (_) {
      // Nouvel essai au prochain démarrage.
    }
  }

  void _open(PushTarget target) {
    if (onOpen == null) {
      _pendingOpen = target;
    } else {
      onOpen!(target);
    }
  }

  static PushTarget _target(RemoteMessage m) =>
      PushTarget.fromData(m.data, title: m.notification?.title, body: m.notification?.body);
}
