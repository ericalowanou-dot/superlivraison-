import 'dart:async';
import 'dart:io' show File;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../api/live.dart';
import '../models.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'call_screen.dart';

/// Discussion en direct entre le client et le livreur d'une course :
/// texte, vocal, photo, position, avec accusés de réception et de lecture.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.orderId, required this.reference});

  final int orderId;
  final String reference;

  /// La discussion affichée en ce moment : ses notifications ne s'affichent pas en double.
  static int? visibleOrderId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  // Sans connexion en direct, l'écran interroge l'API souvent ; avec, seulement par sécurité.
  static const _pollOffline = Duration(seconds: 4);
  static const _pollOnline = Duration(seconds: 30);
  static const _maxRecording = Duration(minutes: 5);
  static const _readBlue = Color(0xFF0B5CAD);

  final _text = TextEditingController();
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final _audioFiles = <int, String>{};

  final List<ChatMessage> _messages = [];
  int? _me;
  ChatPeer? _peer;
  bool _canSend = false;
  bool _hasCourier = true;
  bool _loading = true;
  Object? _error;

  LiveChannel? _live;
  bool _connected = false;
  Timer? _poll;
  DateTime _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);
  bool _fetching = false;

  bool _resumed = true;
  bool _peerTyping = false;
  Timer? _typingTimer;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);

  bool _recording = false;
  DateTime? _recordStart;
  Timer? _recordTick;
  Timer? _recordLimit;

  String? _playing;
  Duration _playPosition = Duration.zero;
  Duration _playLength = Duration.zero;
  final List<StreamSubscription<dynamic>> _playerSubs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ChatScreen.visibleOrderId = widget.orderId;

    _playerSubs
      ..add(_player.onPlayerComplete.listen((_) => setState(() {
            _playing = null;
            _playPosition = Duration.zero;
          })))
      ..add(_player.onPositionChanged.listen((p) => setState(() => _playPosition = p)))
      ..add(_player.onDurationChanged.listen((d) => setState(() => _playLength = d)));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _live = LiveChannel(
        api: AppScope.api(context),
        channel: 'private-orders.${widget.orderId}',
        onEvent: _onLive,
        onConnection: (connected) {
          if (!mounted) return;
          setState(() => _connected = connected);
          // Rattrape ce qui a pu arriver pendant la coupure.
          if (connected) _fetch();
        },
      )..connect();
      _fetch();
      _poll = Timer.periodic(_pollOffline, (_) {
        if (!_connected || DateTime.now().difference(_lastFetch) >= _pollOnline) _fetch();
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (ChatScreen.visibleOrderId == widget.orderId) ChatScreen.visibleOrderId = null;
    _poll?.cancel();
    _typingTimer?.cancel();
    _recordTick?.cancel();
    _recordLimit?.cancel();
    _live?.close();
    for (final sub in _playerSubs) {
      sub.cancel();
    }
    _player.dispose();
    _recorder.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) _fetch();
  }

  ApiClient get _api => AppScope.api(context);

  String get _base => '/orders/${widget.orderId}';

  // ---------------------------------------------------------------- Données

  Future<void> _fetch() async {
    if (_fetching || !mounted) return;
    _fetching = true;

    try {
      final data = await _api.get('$_base/messages') as Map<String, dynamic>;
      if (!mounted) return;
      final meta = data['meta'] as Map<String, dynamic>;

      setState(() {
        _me = meta['me'] as int;
        _canSend = meta['can_send'] as bool;
        _hasCourier = meta['has_courier'] as bool;
        _peer = meta['peer'] == null ? null : ChatPeer.fromJson(meta['peer'] as Map<String, dynamic>);
        for (final raw in data['data'] as List) {
          _merge(ChatMessage.fromJson(raw as Map<String, dynamic>));
        }
        _error = null;
        _loading = false;
      });
      _lastFetch = DateTime.now();
      _markRead();
      _retryFailed();
    } catch (e) {
      if (mounted) setState(() => _error = _messages.isEmpty ? e : null);
      if (mounted && _loading) setState(() => _loading = false);
    } finally {
      _fetching = false;
    }
  }

  /// Ajoute un message du serveur, ou met à jour celui déjà affiché.
  void _merge(ChatMessage server) {
    final index = _messages.indexWhere(
      (m) => (m.id != null && m.id == server.id) || (m.clientUuid == server.clientUuid && m.senderId == server.senderId),
    );

    if (index == -1) {
      _messages.add(server);
    } else {
      final current = _messages[index];
      current.absorb(server);
      current.deliveredAt = server.deliveredAt ?? current.deliveredAt;
      current.readAt = server.readAt ?? current.readAt;
    }

    _messages.sort((a, b) {
      if (a.id == null && b.id == null) return a.createdAt.compareTo(b.createdAt);
      if (a.id == null) return 1;
      if (b.id == null) return -1;
      return a.id!.compareTo(b.id!);
    });
  }

  void _onLive(String event, Map<String, dynamic> data) {
    if (!mounted) return;

    switch (event) {
      case 'message.sent':
        final message = ChatMessage.fromJson(data['message'] as Map<String, dynamic>);
        setState(() {
          _merge(message);
          if (message.senderId != _me) _peerTyping = false;
        });
        if (message.senderId != _me) {
          if (_resumed) {
            _markRead();
          } else {
            _receipt(read: false, upTo: message.id);
          }
        }
      case 'message.receipt':
        if (data['reader_id'] == _me) return;
        final upTo = data['up_to_id'] as int;
        final delivered = DateTime.tryParse(data['delivered_at'] as String? ?? '')?.toLocal();
        final read = DateTime.tryParse(data['read_at'] as String? ?? '')?.toLocal();
        setState(() {
          for (final m in _messages) {
            if (m.senderId != _me || m.id == null || m.id! > upTo) continue;
            m.deliveredAt ??= delivered;
            if (read != null) m.readAt ??= read;
          }
        });
      case 'user.typing':
        if (data['user_id'] == _me) return;
        _typingTimer?.cancel();
        setState(() => _peerTyping = true);
        _typingTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _peerTyping = false);
        });
    }
  }

  /// L'écran est affiché : les messages reçus passent en « lu » chez l'expéditeur.
  void _markRead() {
    if (!_resumed || _me == null) return;

    final unread = _messages.where((m) => m.senderId != _me && m.id != null && m.readAt == null);
    if (unread.isEmpty) return;

    final upTo = unread.map((m) => m.id!).reduce((a, b) => a > b ? a : b);
    final now = DateTime.now();
    for (final m in unread) {
      m.readAt = now;
    }
    _receipt(read: true, upTo: upTo);
  }

  Future<void> _receipt({required bool read, int? upTo}) async {
    try {
      await _api.post('$_base/messages/receipt', {'read': read, 'up_to_id': ?upTo});
    } catch (_) {
      // Le prochain passage refera l'accusé.
    }
  }

  // ---------------------------------------------------------------- Envoi

  ChatMessage _draft(String type, {String? body, String? localPath, int? seconds, double? lat, double? lng}) {
    return ChatMessage(
      clientUuid: const Uuid().v4(),
      senderId: _me!,
      type: type,
      body: body,
      localPath: localPath,
      durationSeconds: seconds,
      lat: lat,
      lng: lng,
      createdAt: DateTime.now(),
      state: SendState.sending,
    );
  }

  Future<void> _post(ChatMessage message) async {
    setState(() {
      if (!_messages.contains(message)) _messages.add(message);
      message.state = SendState.sending;
    });

    try {
      final fields = {'client_uuid': message.clientUuid, 'type': message.type};
      final dynamic data = switch (message.type) {
        'voice' => await _api.upload('$_base/messages', 'audio', message.localPath!, kIsWeb ? 'vocal.wav' : 'vocal.m4a', {
            ...fields,
            if (message.durationSeconds != null) 'duration_seconds': '${message.durationSeconds}',
          }),
        'image' => await _api.postForm('$_base/messages', fields, fileField: 'image', file: XFile(message.localPath!)),
        'location' => await _api.post('$_base/messages', {...fields, 'lat': message.lat, 'lng': message.lng}),
        _ => await _api.post('$_base/messages', {...fields, 'body': message.body}),
      };

      if (mounted) setState(() => _merge(ChatMessage.fromJson(data as Map<String, dynamic>)));
    } on NetworkException {
      // Repart tout seul au retour du réseau.
      if (mounted) setState(() => message.state = SendState.failed);
    } catch (e) {
      if (!mounted) return;
      setState(() => message.state = SendState.failed);
      showMessage(context, errorText(e));
    }
  }

  void _retryFailed() {
    for (final m in _messages.where((m) => m.state == SendState.failed).toList()) {
      _post(m);
    }
  }

  void _sendText() {
    final body = _text.text.trim();
    if (body.isEmpty || _me == null) return;
    _text.clear();
    setState(() {});
    _post(_draft('text', body: body));
  }

  void _onTyping(String value) {
    setState(() {});
    if (value.trim().isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastTypingSent) < const Duration(seconds: 3)) return;
    _lastTypingSent = now;
    _api.post('$_base/typing').catchError((_) => null);
  }

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Prendre une photo'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir une photo'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.my_location),
              title: const Text('Envoyer ma position'),
              onTap: () => Navigator.pop(context, 'location'),
            ),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;
    if (choice == 'location') return _sendLocation();

    final image = await ImagePicker().pickImage(
      source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (image != null && mounted) _post(_draft('image', localPath: image.path));
  }

  Future<void> _sendLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) showMessage(context, 'Autorisez la position pour la partager.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      if (mounted) _post(_draft('location', lat: position.latitude, lng: position.longitude));
    } catch (_) {
      if (mounted) showMessage(context, 'Position introuvable. Réessayez à l\'extérieur.');
    }
  }

  // ---------------------------------------------------------------- Vocal

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) showMessage(context, 'Autorisez le micro pour envoyer un vocal.');
      return;
    }

    final String path;
    if (kIsWeb) {
      path = 'vocal.wav';
    } else {
      final dir = await getApplicationDocumentsDirectory();
      path = '${dir.path}/chat-${const Uuid().v4()}.m4a';
    }

    await _player.stop();
    await _recorder.start(
      const RecordConfig(encoder: kIsWeb ? AudioEncoder.wav : AudioEncoder.aacLc, bitRate: 48000, sampleRate: 16000, numChannels: 1),
      path: path,
    );

    _recordLimit = Timer(_maxRecording, () => _stopRecording(send: true));
    _recordTick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    setState(() {
      _recording = true;
      _playing = null;
      _recordStart = DateTime.now();
    });
  }

  Future<void> _stopRecording({required bool send}) async {
    _recordLimit?.cancel();
    _recordTick?.cancel();
    final path = await _recorder.stop();
    final seconds = DateTime.now().difference(_recordStart!).inSeconds;
    if (!mounted) return;
    setState(() => _recording = false);

    if (!send || path == null) {
      if (!kIsWeb && path != null) File(path).delete().catchError((_) => File(path));
      return;
    }
    if (seconds < 1) return showMessage(context, 'Vocal trop court.');

    _post(_draft('voice', localPath: path, seconds: seconds));
  }

  Future<void> _togglePlay(ChatMessage message) async {
    final key = message.clientUuid;
    if (_playing == key) {
      await _player.pause();
      setState(() => _playing = null);
      return;
    }

    try {
      setState(() {
        _playing = key;
        _playPosition = Duration.zero;
        _playLength = Duration(seconds: message.durationSeconds ?? 0);
      });
      await _player.stop();
      await _player.play(await _audioSource(message));
    } catch (_) {
      if (!mounted) return;
      setState(() => _playing = null);
      showMessage(context, 'Lecture du vocal impossible.');
    }
  }

  Future<Source> _audioSource(ChatMessage message) async {
    final local = message.localPath;
    if (local != null) return kIsWeb ? UrlSource(local) : DeviceFileSource(local);

    final id = message.id!;
    final cached = _audioFiles[id];
    if (cached != null) return DeviceFileSource(cached);

    final bytes = await _api.download('/messages/$id/media');
    if (kIsWeb) return BytesSource(bytes);

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/chat-$id.m4a');
    await file.writeAsBytes(bytes);
    _audioFiles[id] = file.path;
    return DeviceFileSource(file.path);
  }

  // ---------------------------------------------------------------- Affichage

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final peer = _peer;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Palette.sky,
              foregroundColor: Palette.onSky,
              child: Icon(peer?.isCourier ?? true ? Icons.delivery_dining : Icons.person_outline, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(peer?.name ?? 'Discussion', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                  Text(
                    _peerTyping ? 'écrit…' : '${peer?.isCourier ?? true ? 'Livreur' : 'Client'} · ${widget.reference}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _peerTyping ? p.link : p.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_canSend) ...[
            IconButton(
              tooltip: 'Appel vidéo',
              icon: const Icon(Icons.videocam_outlined),
              onPressed: () => startCall(context, orderId: widget.orderId, video: true),
            ),
            IconButton(
              tooltip: 'Appel vocal',
              icon: const Icon(Icons.call_outlined),
              onPressed: () => startCall(context, orderId: widget.orderId, video: false),
            ),
          ],
          if (peer?.phone != null)
            PopupMenuButton<String>(
              tooltip: 'Plus',
              onSelected: (_) => callPhone(context, peer!.phone!),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'phone', child: Text('Appel téléphonique classique')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!_connected && !_loading && _error == null)
              Container(
                width: double.infinity,
                color: p.soft,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Muted('Connexion en direct en cours…', size: 12, align: TextAlign.center),
              ),
            Expanded(child: _body()),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorRetry(error: _error!, onRetry: _fetch);

    if (!_hasCourier) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Muted('La discussion s\'ouvrira dès qu\'un livreur sera affecté à votre course.', align: TextAlign.center),
        ),
      );
    }

    if (_messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Muted('Aucun message. Écrivez, envoyez un vocal, une photo ou votre position.', align: TextAlign.center),
        ),
      );
    }

    // Liste inversée : le dernier message reste en bas, au-dessus du clavier.
    final items = _messages.reversed.toList();

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final message = items[index];
        final older = index + 1 < items.length ? items[index + 1] : null;
        final newDay = older == null || !_sameDay(older.createdAt, message.createdAt);

        return Column(
          children: [
            if (newDay) _DayChip(message.createdAt),
            _bubble(message),
          ],
        );
      },
    );
  }

  Widget _bubble(ChatMessage message) {
    final p = Palette.of(context);
    final mine = message.senderId == _me;
    final fg = mine ? Palette.onSky : p.ink;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        child: GestureDetector(
          onTap: message.state == SendState.failed ? () => _post(message) : null,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: EdgeInsets.all(message.type == 'image' ? 4 : 10),
            decoration: BoxDecoration(
              color: mine ? Palette.sky : p.surface,
              border: mine ? null : Border.all(color: p.line),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mine ? 16 : 4),
                bottomRight: Radius.circular(mine ? 4 : 16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _content(message, fg),
                const SizedBox(height: 4),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: message.type == 'image' ? 6 : 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.state == SendState.failed)
                        Text('Non envoyé · toucher pour renvoyer  ', style: TextStyle(fontSize: 11, color: mine ? Palette.onSky : p.warn)),
                      Text(_time(message.createdAt), style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.7))),
                      if (mine && message.type != 'call') ...[const SizedBox(width: 4), _ticks(message, fg)],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ✓ envoyé, ✓✓ reçu, ✓✓ bleu lu.
  Widget _ticks(ChatMessage message, Color fg) {
    final dim = fg.withValues(alpha: 0.65);

    return switch (message.state) {
      SendState.sending => Icon(Icons.schedule, size: 14, color: dim),
      SendState.failed => Icon(Icons.error_outline, size: 15, color: Palette.of(context).warn),
      SendState.sent when message.readAt != null => const Icon(Icons.done_all, size: 16, color: _readBlue),
      SendState.sent when message.deliveredAt != null => Icon(Icons.done_all, size: 16, color: dim),
      SendState.sent => Icon(Icons.done, size: 16, color: dim),
    };
  }

  Widget _content(ChatMessage message, Color fg) {
    switch (message.type) {
      case 'voice':
        final playing = _playing == message.clientUuid;
        final total = playing && _playLength > Duration.zero ? _playLength : Duration(seconds: message.durationSeconds ?? 0);
        final progress = playing && total.inMilliseconds > 0 ? (_playPosition.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0) : 0.0;

        return SizedBox(
          width: 220,
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: playing ? 'Pause' : 'Écouter',
                icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 34, color: fg),
                onPressed: message.localPath == null && message.id == null ? null : () => _togglePlay(message),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: progress, minHeight: 4, color: fg, backgroundColor: fg.withValues(alpha: 0.2)),
                    ),
                    const SizedBox(height: 4),
                    Text(_clock(playing ? _playPosition : total), style: TextStyle(fontSize: 12, color: fg)),
                  ],
                ),
              ),
            ],
          ),
        );

      case 'image':
        final Widget image;
        if (message.localPath != null) {
          image = kIsWeb
              ? Image.network(message.localPath!, width: 230, height: 230, fit: BoxFit.cover)
              : Image.file(File(message.localPath!), width: 230, height: 230, fit: BoxFit.cover);
        } else if (message.id != null) {
          image = AuthImage('/messages/${message.id}/media', width: 230, height: 230);
        } else {
          image = const SizedBox(width: 230, height: 230);
        }

        return GestureDetector(
          onTap: () => _showImage(image is AuthImage ? AuthImage('/messages/${message.id}/media', fit: BoxFit.contain) : image),
          child: ClipRRect(borderRadius: BorderRadius.circular(12), child: image),
        );

      case 'location':
        return InkWell(
          onTap: () => openMap(context, message.lat!, message.lng!),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.place, color: fg, size: 30),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Position partagée', style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
                  Text('Toucher pour ouvrir la carte', style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.75))),
                ],
              ),
            ],
          ),
        );

      case 'call':
        return _callContent(message, fg);

      default:
        return Text(message.body ?? '', style: TextStyle(fontSize: 15, color: fg));
    }
  }

  /// « Appel vidéo sortant · 2 min 14 », « Appel vocal manqué »… Toucher pour rappeler.
  Widget _callContent(ChatMessage message, Color fg) {
    final call = message.call;
    final mine = message.senderId == _me;
    final video = call?.video ?? false;
    final kind = video ? 'Appel vidéo' : 'Appel vocal';
    final missed = !mine && call?.status == 'missed';

    final (String title, IconData arrow) = switch (call?.status) {
      'ended' => (mine ? '$kind sortant' : '$kind entrant', mine ? Icons.call_made : Icons.call_received),
      'declined' => ('$kind refusé', mine ? Icons.call_made : Icons.call_received),
      'missed' => (mine ? '$kind · Sans réponse' : '$kind manqué', mine ? Icons.call_made : Icons.call_missed),
      _ => (kind, Icons.call),
    };
    final seconds = call?.durationSeconds;
    final subtitle = call?.status == 'ended' && seconds != null ? _callLength(seconds) : 'Toucher pour rappeler';

    return InkWell(
      onTap: _canSend ? () => startCall(context, orderId: widget.orderId, video: video) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: fg.withValues(alpha: 0.15),
            child: Icon(video ? Icons.videocam : Icons.call, size: 20, color: missed ? Palette.of(context).warn : fg),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: missed ? Palette.of(context).warn : fg)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(arrow, size: 14, color: missed ? Palette.of(context).warn : fg.withValues(alpha: 0.75)),
                    const SizedBox(width: 4),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.75))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _callLength(int seconds) {
    if (seconds < 60) return '$seconds s';
    final m = seconds ~/ 60, s = seconds % 60;
    return s == 0 ? '$m min' : '$m min ${s.toString().padLeft(2, '0')}';
  }

  void _showImage(Widget image) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(child: InteractiveViewer(child: Center(child: image))),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: 'Fermer',
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    final p = Palette.of(context);

    if (_loading || _error != null || !_hasCourier) return const SizedBox.shrink();

    if (!_canSend) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        color: p.soft,
        child: const Muted('Course terminée : la discussion est fermée.', align: TextAlign.center),
      );
    }

    if (_recording) {
      final elapsed = DateTime.now().difference(_recordStart!);

      return Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.line))),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Annuler le vocal',
              icon: Icon(Icons.delete_outline, color: p.warn),
              onPressed: () => _stopRecording(send: false),
            ),
            Icon(Icons.fiber_manual_record, color: p.warn, size: 14),
            const SizedBox(width: 6),
            Expanded(child: Text('Enregistrement  ${_clock(elapsed)}', style: const TextStyle(fontWeight: FontWeight.w600))),
            _RoundButton(icon: Icons.send, tooltip: 'Envoyer le vocal', onPressed: () => _stopRecording(send: true)),
          ],
        ),
      );
    }

    final hasText = _text.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
      decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(tooltip: 'Joindre', icon: const Icon(Icons.add_circle_outline), onPressed: _attach),
          Expanded(
            child: TextField(
              controller: _text,
              minLines: 1,
              maxLines: 5,
              maxLength: 4000,
              textCapitalization: TextCapitalization.sentences,
              onChanged: _onTyping,
              decoration: const InputDecoration(
                hintText: 'Message',
                counterText: '',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 6),
          hasText
              ? _RoundButton(icon: Icons.send, tooltip: 'Envoyer', onPressed: _sendText)
              : _RoundButton(icon: Icons.mic_none, tooltip: 'Enregistrer un vocal', onPressed: _startRecording),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static String _time(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _clock(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Palette.sky,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(padding: const EdgeInsets.all(11), child: Icon(icon, color: Palette.onSky, size: 22)),
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip(this.date);

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final label = day == today
        ? "Aujourd'hui"
        : today.difference(day).inDays == 1
            ? 'Hier'
            : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: p.soft, borderRadius: BorderRadius.circular(10)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)),
      ),
    );
  }
}

/// Bouton « Discuter » avec le nombre de messages non lus.
class ChatButton extends StatelessWidget {
  const ChatButton({super.key, required this.order, required this.label, this.onReturn});

  final Order order;
  final String label;
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) {
    final unread = order.unreadMessages;

    return OutlinedButton.icon(
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        child: const Icon(Icons.chat_bubble_outline, size: 20),
      ),
      label: Text(label),
      onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChatScreen(orderId: order.id, reference: order.reference)),
        );
        onReturn?.call();
      },
    );
  }
}
