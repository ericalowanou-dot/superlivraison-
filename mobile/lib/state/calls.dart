import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../screens/call_screen.dart';
import 'session.dart';

/// Ce qu'il faut pour rejoindre un appel : donné par le serveur, avec un jeton à la place de toute clé secrète.
class CallJoin {
  CallJoin.fromJson(Map<String, dynamic> j)
      : callId = (j['call'] as Map<String, dynamic>)['id'] as int,
        orderId = (j['call'] as Map<String, dynamic>)['order_id'] as int,
        video = (j['call'] as Map<String, dynamic>)['video'] as bool,
        status = (j['call'] as Map<String, dynamic>)['status'] as String,
        peerName = ((j['peer'] as Map<String, dynamic>?)?['name'] as String?) ?? 'Votre contact',
        appId = (j['zego'] as Map<String, dynamic>)['app_id'] as int,
        token = (j['zego'] as Map<String, dynamic>)['token'] as String,
        roomId = (j['zego'] as Map<String, dynamic>)['room_id'] as String,
        userId = (j['zego'] as Map<String, dynamic>)['user_id'] as String,
        streamId = (j['zego'] as Map<String, dynamic>)['stream_id'] as String,
        peerStreamId = (j['zego'] as Map<String, dynamic>)['peer_stream_id'] as String;

  final int callId, orderId, appId;
  final bool video;
  final String status, peerName, token, roomId, userId, streamId, peerStreamId;
}

/// Identifiant de la sonnerie du téléphone pour un appel du serveur (même valeur partout).
String ringId(int callId) => const Uuid().v5(Namespace.url.value, 'https://superlivraison.app/calls/$callId');

/// Fait sonner le téléphone en plein écran, même appli fermée ou écran verrouillé.
Future<void> showIncomingCall(Map<String, dynamic> data) async {
  final callId = int.tryParse('${data['call_id']}');
  if (callId == null) return;
  final video = data['video'] == '1';
  final reference = data['reference'] as String? ?? '';

  await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
    id: ringId(callId),
    nameCaller: data['caller_name'] as String? ?? 'Superlivraison',
    appName: 'Superlivraison',
    handle: '${video ? 'Appel vidéo' : 'Appel vocal'}${reference.isEmpty ? '' : ' · $reference'}',
    type: video ? 1 : 0,
    duration: 45000,
    // Le serveur envoie lui-même la notification d'appel manqué.
    missedCallNotification: const NotificationParams(showNotification: false),
    callingNotification: const NotificationParams(showNotification: false),
    extra: {
      'call_id': '$callId',
      'order_id': '${data['order_id']}',
      'reference': reference,
      'video': video ? '1' : '0',
      'caller_name': data['caller_name'] ?? '',
    },
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      isShowCallID: false,
      isShowFullLockedScreen: true,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#0B5CAD',
      actionColor: '#25D366',
      textColor: '#FFFFFF',
      incomingCallNotificationChannelName: 'Appels entrants',
      missedCallNotificationChannelName: 'Appels manqués',
      textAccept: 'Accepter',
      textDecline: 'Refuser',
    ),
  ));
}

Future<void> stopRinging(int callId) => FlutterCallkitIncoming.endCall(ringId(callId));

int? _callIdOf(CallKitParams params) => int.tryParse('${params.extra?['call_id'] ?? ''}');

/// Sonnerie refusée alors que l'appli était fermée : on prévient le serveur pour que l'appelant le sache.
@pragma('vm:entry-point')
Future<void> callkitBackgroundHandler(CallEvent event) async {
  if (event is! CallEventActionCallDecline) return;
  final callId = _callIdOf(event.callKitParams);
  final token = await Session.storedToken();
  if (callId == null || token == null) return;

  try {
    await (ApiClient()..token = token).post('/calls/$callId/end');
  } catch (_) {
    // Sans réponse, l'appel sera noté comme manqué.
  }
}

/// Appels de l'appli : sonnerie, décroché depuis l'écran verrouillé, ouverture de l'écran d'appel.
class CallManager {
  CallManager(this.api, this.navigator);

  final ApiClient api;
  final GlobalKey<NavigatorState> navigator;

  /// Appel affiché à l'écran en ce moment : un seul à la fois.
  static int? activeCallId;

  final Set<int> _handled = {};
  StreamSubscription<CallEvent?>? _events;

  Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      _events = FlutterCallkitIncoming.onEvent.listen(_onEvent);
      await FlutterCallkitIncoming.onBackgroundMessage(callkitBackgroundHandler);
    } catch (e) {
      debugPrint('Sonnerie des appels indisponible : $e');
    }
  }

  /// Après le démarrage : un appel décroché pendant que l'appli était fermée s'ouvre maintenant.
  Future<void> resumeAccepted() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android || api.token == null) return;

    try {
      for (final params in await FlutterCallkitIncoming.activeCalls()) {
        if (params.isAccepted) await _answer(params);
      }
    } catch (_) {
      // Rien à reprendre.
    }
  }

  /// Message silencieux de Firebase, appli ouverte ou fermée.
  Future<void> onPushData(Map<String, dynamic> data) async {
    final callId = int.tryParse('${data['call_id'] ?? ''}');
    if (callId == null) return;

    switch (data['kind']) {
      case 'call':
        if (activeCallId != null) return; // Déjà en ligne : le serveur notera l'appel comme manqué.
        await showIncomingCall(data);
      case 'call_ended':
        await stopRinging(callId);
    }
  }

  /// Demande les autorisations utiles une fois connecté : notifications et écran plein en sonnerie.
  Future<void> requestPermissions() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        'title': 'Notifications',
        'rationaleMessagePermission': 'Les notifications servent à vous prévenir des messages et des appels.',
        'postNotificationMessageRequired': 'Autorisez les notifications dans les réglages pour recevoir les appels.',
      });
      if (!await FlutterCallkitIncoming.canUseFullScreenIntent()) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
      }
    } catch (_) {
      // Le téléphone sonnera quand même, en simple notification.
    }
  }

  void dispose() => _events?.cancel();

  Future<void> _onEvent(CallEvent? event) async {
    switch (event) {
      case CallEventActionCallAccept(:final callKitParams):
        await _answer(callKitParams);
      case CallEventActionCallDecline(:final callKitParams):
        final callId = _callIdOf(callKitParams);
        if (callId != null && _handled.add(callId)) {
          try {
            await api.post('/calls/$callId/end');
          } catch (_) {
            // Sans réponse, l'appel sera noté comme manqué.
          }
        }
      default:
        break;
    }
  }

  Future<void> _answer(CallKitParams params) async {
    final callId = _callIdOf(params);
    if (callId == null || !_handled.add(callId)) return;

    try {
      final join = CallJoin.fromJson(await api.post('/calls/$callId/accept') as Map<String, dynamic>);
      final nav = await _navigatorReady();
      await nav?.push(MaterialPageRoute(builder: (_) => CallScreen(join: join, outgoing: false)));
    } catch (e) {
      await stopRinging(callId);
      final context = navigator.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Cet appel est terminé.')));
      }
    }
  }

  /// Au lancement par la sonnerie, l'interface met un instant à être prête.
  Future<NavigatorState?> _navigatorReady() async {
    for (var i = 0; i < 50 && navigator.currentState == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return navigator.currentState;
  }
}
