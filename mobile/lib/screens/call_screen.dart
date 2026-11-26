import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:zego_express_engine/zego_express_engine.dart';

import '../api/api_client.dart';
import '../api/live.dart';
import '../state/calls.dart';
import '../state/session.dart';
import '../widgets.dart';

/// Lance un appel depuis la discussion et ouvre l'écran d'appel.
Future<void> startCall(BuildContext context, {required int orderId, required bool video}) async {
  if (CallManager.activeCallId != null) return;
  final api = AppScope.api(context);
  final navigator = Navigator.of(context);

  try {
    final join = CallJoin.fromJson(await api.post('/orders/$orderId/calls', {'video': video}) as Map<String, dynamic>);
    await navigator.push(MaterialPageRoute(builder: (_) => CallScreen(join: join, outgoing: true)));
  } catch (e) {
    if (context.mounted) showMessage(context, errorText(e));
  }
}

/// Écran d'un appel audio ou vidéo, comme sur WhatsApp : l'autre personne en grand,
/// sa propre caméra en vignette, et les commandes en bas.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.join, required this.outgoing});

  final CallJoin join;
  final bool outgoing;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late String _status = widget.join.status;
  String? _endText;
  DateTime? _answeredAt;
  Timer? _tick;
  Timer? _poll;
  LiveChannel? _live;

  bool _engineReady = false;
  bool _micOn = true;
  late bool _cameraOn = widget.join.video;
  bool _frontCamera = true;
  late bool _speaker = widget.join.video;

  Widget? _localView;
  int? _localViewId;
  Widget? _remoteView;
  int? _remoteViewId;
  bool _peerPublishing = false;
  late bool _peerCameraOn = widget.join.video;

  CallJoin get _join => widget.join;

  bool get _ongoing => _status == 'ongoing';

  bool get _finished => _endText != null;

  @override
  void initState() {
    super.initState();
    CallManager.activeCallId = _join.callId;
    if (_ongoing) _answeredAt = DateTime.now();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _ongoing) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _live = LiveChannel(api: _api, channel: 'private-orders.${_join.orderId}', onEvent: _onLive)..connect();
      // Par sécurité, si la connexion en direct ne passe pas.
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
      _joinRoom();
    });
  }

  @override
  void dispose() {
    if (CallManager.activeCallId == _join.callId) CallManager.activeCallId = null;
    _tick?.cancel();
    _poll?.cancel();
    _live?.close();
    _leaveRoom();
    super.dispose();
  }

  ApiClient get _api => AppScope.api(context);

  // ---------------------------------------------------------------- État de l'appel

  void _onLive(String event, Map<String, dynamic> data) {
    final call = data['call'];
    if (call is! Map<String, dynamic> || call['id'] != _join.callId) return;
    _apply(call['status'] as String);
  }

  Future<void> _refresh() async {
    if (_finished) return;
    try {
      final data = await _api.get('/calls/${_join.callId}') as Map<String, dynamic>;
      _apply((data['call'] as Map<String, dynamic>)['status'] as String);
    } catch (_) {
      // Nouvel essai au prochain passage.
    }
  }

  void _apply(String status) {
    if (!mounted || _finished || status == _status) return;

    if (status == 'ongoing') {
      setState(() {
        _status = status;
        _answeredAt = DateTime.now();
      });
      return;
    }

    if (status != 'ringing') {
      _status = status;
      _finish(switch (status) {
        'declined' => widget.outgoing ? 'Appel refusé' : 'Appel terminé',
        'missed' => widget.outgoing ? 'Pas de réponse' : 'Appel manqué',
        _ => 'Appel terminé',
      });
    }
  }

  Future<void> _hangUp() async {
    if (_finished) return;
    _finish('Appel terminé');
    try {
      await _api.post('/calls/${_join.callId}/end');
    } catch (_) {
      // L'autre téléphone verra la fin de l'appel quand il quittera la salle.
    }
  }

  void _finish(String text) {
    if (_finished) return;
    setState(() => _endText = text);
    _poll?.cancel();
    _leaveRoom();
    stopRinging(_join.callId);
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  // ---------------------------------------------------------------- Son et image (ZEGOCLOUD)

  Future<void> _joinRoom() async {
    final permissions = await [Permission.microphone, if (_join.video) Permission.camera].request();
    if (!mounted || _finished) return;

    if (permissions[Permission.microphone] != PermissionStatus.granted) {
      showMessage(context, 'Autorisez le micro pour passer des appels.');
      return _hangUp();
    }
    if (_join.video && permissions[Permission.camera] != PermissionStatus.granted) {
      _cameraOn = false;
    }

    try {
      await ZegoExpressEngine.createEngineWithProfile(ZegoEngineProfile(_join.appId, ZegoScenario.StandardVideoCall));
      _engineReady = true;

      ZegoExpressEngine.onRoomStreamUpdate = (roomId, type, streams, _) {
        if (!streams.any((s) => s.streamID == _join.peerStreamId)) return;
        if (type == ZegoUpdateType.Add) {
          _playPeer();
        } else {
          ZegoExpressEngine.instance.stopPlayingStream(_join.peerStreamId);
          if (mounted) setState(() => _peerPublishing = false);
        }
      };
      ZegoExpressEngine.onRemoteCameraStateUpdate = (streamId, state) {
        if (streamId == _join.peerStreamId && mounted) {
          setState(() => _peerCameraOn = state == ZegoRemoteDeviceState.Open);
        }
      };

      // Le jeton du serveur ouvre la salle : aucune clé secrète n'est dans l'appli.
      final login = await ZegoExpressEngine.instance.loginRoom(
        _join.roomId,
        ZegoUser(_join.userId, _join.userId),
        config: ZegoRoomConfig(2, true, _join.token),
      );
      if (login.errorCode != 0) throw Exception('code ${login.errorCode}');
      if (!mounted || _finished) return _leaveRoom();

      await ZegoExpressEngine.instance.enableCamera(_cameraOn);
      if (_join.video && _cameraOn) {
        final view = await ZegoExpressEngine.instance.createCanvasView((viewId) {
          _localViewId = viewId;
          ZegoExpressEngine.instance.startPreview(canvas: ZegoCanvas(viewId, viewMode: ZegoViewMode.AspectFill));
        });
        if (mounted) setState(() => _localView = view);
      }
      await ZegoExpressEngine.instance.setAudioRouteToSpeaker(_speaker);
      await ZegoExpressEngine.instance.startPublishingStream(_join.streamId);
    } catch (e) {
      if (!mounted) return;
      showMessage(context, 'Connexion à l\'appel impossible ($e).');
      await _hangUp();
    }
  }

  Future<void> _playPeer() async {
    if (!_engineReady || _finished) return;
    if (mounted) setState(() => _peerPublishing = true);

    if (!_join.video) {
      await ZegoExpressEngine.instance.startPlayingStream(_join.peerStreamId);
      return;
    }

    if (_remoteViewId != null) {
      await ZegoExpressEngine.instance.startPlayingStream(
        _join.peerStreamId,
        canvas: ZegoCanvas(_remoteViewId!, viewMode: ZegoViewMode.AspectFill),
      );
      return;
    }

    final view = await ZegoExpressEngine.instance.createCanvasView((viewId) {
      _remoteViewId = viewId;
      ZegoExpressEngine.instance.startPlayingStream(
        _join.peerStreamId,
        canvas: ZegoCanvas(viewId, viewMode: ZegoViewMode.AspectFill),
      );
    });
    if (mounted) setState(() => _remoteView = view);
  }

  void _leaveRoom() {
    if (!_engineReady) return;
    _engineReady = false;
    ZegoExpressEngine.onRoomStreamUpdate = null;
    ZegoExpressEngine.onRemoteCameraStateUpdate = null;

    final engine = ZegoExpressEngine.instance;
    final local = _localViewId, remote = _remoteViewId;
    () async {
      try {
        await engine.stopPublishingStream();
        await engine.stopPreview();
        await engine.logoutRoom(_join.roomId);
        if (local != null) await engine.destroyCanvasView(local);
        if (remote != null) await engine.destroyCanvasView(remote);
      } finally {
        await ZegoExpressEngine.destroyEngine();
      }
    }();
  }

  Future<void> _toggleMic() async {
    setState(() => _micOn = !_micOn);
    if (_engineReady) await ZegoExpressEngine.instance.muteMicrophone(!_micOn);
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _speaker = !_speaker);
    if (_engineReady) await ZegoExpressEngine.instance.setAudioRouteToSpeaker(_speaker);
  }

  Future<void> _toggleCamera() async {
    setState(() => _cameraOn = !_cameraOn);
    if (!_engineReady) return;
    await ZegoExpressEngine.instance.enableCamera(_cameraOn);
    if (_cameraOn && _localView == null) {
      final view = await ZegoExpressEngine.instance.createCanvasView((viewId) {
        _localViewId = viewId;
        ZegoExpressEngine.instance.startPreview(canvas: ZegoCanvas(viewId, viewMode: ZegoViewMode.AspectFill));
      });
      if (mounted) setState(() => _localView = view);
    }
  }

  Future<void> _switchCamera() async {
    setState(() => _frontCamera = !_frontCamera);
    if (_engineReady) await ZegoExpressEngine.instance.useFrontCamera(_frontCamera);
  }

  // ---------------------------------------------------------------- Affichage

  String get _statusText {
    if (_endText != null) return _endText!;
    if (_ongoing) {
      if (!_peerPublishing) return 'Connexion…';
      final seconds = DateTime.now().difference(_answeredAt ?? DateTime.now()).inSeconds;
      final m = seconds ~/ 60, s = seconds % 60;
      return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return widget.outgoing ? 'Ça sonne…' : 'Connexion…';
  }

  @override
  Widget build(BuildContext context) {
    final showRemoteVideo = _join.video && _remoteView != null && _peerPublishing && _peerCameraOn && !_finished;

    return PopScope(
      canPop: _finished,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B141A),
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (showRemoteVideo) Positioned.fill(child: _remoteView!),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  if (!showRemoteVideo) ...[
                    CircleAvatar(
                      radius: 52,
                      backgroundColor: Colors.white24,
                      child: Text(
                        _join.peerName.isEmpty ? '?' : _join.peerName.characters.first.toUpperCase(),
                        style: const TextStyle(fontSize: 42, color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Text(
                    _join.peerName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 26, color: Colors.white, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 6)]),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_join.video ? 'Appel vidéo' : 'Appel vocal'} · $_statusText',
                    style: const TextStyle(fontSize: 15, color: Colors.white70, shadows: [Shadow(blurRadius: 6)]),
                  ),
                  const Spacer(),
                  _controls(),
                  const SizedBox(height: 28),
                ],
              ),
            ),
            if (_join.video && _cameraOn && _localView != null && !_finished)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 16,
                right: 16,
                width: 108,
                height: 156,
                child: ClipRRect(borderRadius: BorderRadius.circular(14), child: _localView!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 18,
      children: [
        _ControlButton(
          icon: _micOn ? Icons.mic : Icons.mic_off,
          label: _micOn ? 'Micro' : 'Micro coupé',
          active: !_micOn,
          onPressed: _finished ? null : _toggleMic,
        ),
        if (_join.video) ...[
          _ControlButton(
            icon: _cameraOn ? Icons.videocam : Icons.videocam_off,
            label: 'Caméra',
            active: !_cameraOn,
            onPressed: _finished ? null : _toggleCamera,
          ),
          _ControlButton(
            icon: Icons.cameraswitch_outlined,
            label: 'Retourner',
            onPressed: _finished || !_cameraOn ? null : _switchCamera,
          ),
        ] else
          _ControlButton(
            icon: _speaker ? Icons.volume_up : Icons.volume_down_outlined,
            label: 'Haut-parleur',
            active: _speaker,
            onPressed: _finished ? null : _toggleSpeaker,
          ),
        _ControlButton(
          icon: Icons.call_end,
          label: 'Raccrocher',
          color: const Color(0xFFE53935),
          onPressed: _finished ? null : _hangUp,
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.icon, required this.label, this.onPressed, this.active = false, this.color});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color ?? (active ? Colors.white : Colors.white24),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 62,
              height: 62,
              child: Icon(icon, size: 28, color: color != null ? Colors.white : (active ? Colors.black87 : Colors.white)),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
