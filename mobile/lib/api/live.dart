import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';

/// Un évènement reçu en direct sur le canal d'une course.
typedef LiveHandler = void Function(String event, Map<String, dynamic> data);

/// Écoute un canal privé du serveur temps réel (Laravel Reverb, protocole Pusher).
///
/// La connexion se rétablit toute seule après une coupure. [onConnection] indique
/// si elle est active : sans elle, l'écran interroge l'API à intervalle court.
class LiveChannel {
  LiveChannel({required this.api, required this.channel, required this.onEvent, this.onConnection});

  static const _key = String.fromEnvironment('REVERB_KEY', defaultValue: 'superlivraison-key');
  static const _url = String.fromEnvironment('REVERB_URL');

  final ApiClient api;

  /// Nom du canal privé, par exemple « private-orders.12 ».
  final String channel;
  final LiveHandler onEvent;
  final void Function(bool connected)? onConnection;

  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  Timer? _ping;
  Duration _activityTimeout = const Duration(seconds: 30);
  int _attempt = 0;
  bool _closed = false;
  bool _connected = false;

  /// Par défaut, le serveur temps réel tourne sur la machine de l'API, port 8080.
  static Uri get _endpoint {
    if (_url.isNotEmpty) return Uri.parse('$_url/app/$_key?protocol=7&client=dart&version=1.0&flash=false');

    final api = Uri.parse(ApiClient.baseUrl);
    final secure = api.scheme == 'https';

    return Uri(
      scheme: secure ? 'wss' : 'ws',
      host: api.host,
      port: secure ? 443 : 8080,
      path: '/app/$_key',
      queryParameters: {'protocol': '7', 'client': 'dart', 'version': '1.0', 'flash': 'false'},
    );
  }

  void connect() {
    if (_closed) return;

    try {
      final socket = WebSocketChannel.connect(_endpoint);
      _socket = socket;
      _subscription = socket.stream.listen(_receive, onError: (_) => _lost(), onDone: _lost, cancelOnError: true);
    } catch (_) {
      _lost();
    }
  }

  void close() {
    _closed = true;
    _retry?.cancel();
    _ping?.cancel();
    _subscription?.cancel();
    _socket?.sink.close();
    _setConnected(false);
  }

  Future<void> _receive(dynamic raw) async {
    final Map<String, dynamic> frame;
    try {
      frame = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final event = frame['event'] as String? ?? '';
    final data = _decode(frame['data']);
    _keepAlive();

    switch (event) {
      case 'pusher:connection_established':
        final timeout = data['activity_timeout'];
        if (timeout is int && timeout > 0) _activityTimeout = Duration(seconds: timeout);
        await _subscribe(data['socket_id'] as String);
      case 'pusher_internal:subscription_succeeded':
        _attempt = 0;
        _setConnected(true);
      case 'pusher:ping':
        _send({'event': 'pusher:pong', 'data': {}});
      case 'pusher:error':
        // Refus du serveur, par exemple une clé inconnue : l'écran reste sur l'interrogation régulière.
        break;
      default:
        if (frame['channel'] == channel && !event.startsWith('pusher')) onEvent(event, data);
    }
  }

  Future<void> _subscribe(String socketId) async {
    try {
      final auth = await api.post('/broadcasting/auth', {'socket_id': socketId, 'channel_name': channel}) as Map<String, dynamic>;
      _send({
        'event': 'pusher:subscribe',
        'data': {'channel': channel, 'auth': auth['auth']},
      });
    } catch (_) {
      _socket?.sink.close();
    }
  }

  /// Sans échange pendant le délai fixé par le serveur, on vérifie que la connexion tient.
  void _keepAlive() {
    _ping?.cancel();
    _ping = Timer(_activityTimeout, () => _send({'event': 'pusher:ping', 'data': {}}));
  }

  void _send(Map<String, dynamic> frame) {
    try {
      _socket?.sink.add(jsonEncode(frame));
    } catch (_) {
      _lost();
    }
  }

  void _lost() {
    _ping?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _socket = null;
    _setConnected(false);
    if (_closed) return;

    // 1 s, 2 s, 4 s… jusqu'à 30 s entre deux tentatives.
    final wait = Duration(seconds: (1 << _attempt.clamp(0, 5)).clamp(1, 30));
    _attempt++;
    _retry?.cancel();
    _retry = Timer(wait, connect);
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    onConnection?.call(value);
  }

  static Map<String, dynamic> _decode(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
        // Donnée non JSON : ignorée.
      }
    }
    return const {};
  }
}
