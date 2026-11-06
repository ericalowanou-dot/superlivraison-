import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../state/outbox.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'map_screen.dart';

class NewOrderScreen extends StatefulWidget {
  const NewOrderScreen({super.key});

  @override
  State<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends State<NewOrderScreen> {
  static const _maxRecording = Duration(minutes: 5);

  final _text = TextEditingController();
  final _landmark = TextEditingController();
  final _recorder = AudioRecorder();
  // Garde le même identifiant si le restaurant renvoie : pas de double commande.
  final _clientUuid = const Uuid().v4();

  bool _recording = false;
  bool _transcribing = false;
  bool _sending = false;
  DateTime? _startedAt;
  Timer? _limit;
  String? _voicePath;
  int? _voiceSeconds;
  int? _voiceNoteId;
  LatLng? _point;

  @override
  void dispose() {
    _limit?.cancel();
    _recorder.dispose();
    _text.dispose();
    _landmark.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_recording) return _stop();

    if (!await _recorder.hasPermission()) {
      if (mounted) showMessage(context, 'Autorisez le micro pour dicter votre demande.');
      return;
    }

    final String path;
    if (kIsWeb) {
      path = 'vocal.wav';
    } else {
      final dir = await getApplicationDocumentsDirectory();
      path = '${dir.path}/vocal-$_clientUuid.m4a';
    }

    await _recorder.start(
      const RecordConfig(encoder: kIsWeb ? AudioEncoder.wav : AudioEncoder.aacLc, bitRate: 48000, sampleRate: 16000, numChannels: 1),
      path: path,
    );

    _limit = Timer(_maxRecording, _stop);
    setState(() {
      _recording = true;
      _startedAt = DateTime.now();
      _voicePath = null;
      _voiceNoteId = null;
    });
  }

  Future<void> _stop() async {
    _limit?.cancel();
    final path = await _recorder.stop();
    final seconds = DateTime.now().difference(_startedAt!).inSeconds;
    if (!mounted) return;

    setState(() {
      _recording = false;
      _voicePath = path;
      _voiceSeconds = seconds < 1 ? 1 : seconds;
    });

    if (path != null) await _transcribe(path);
  }

  /// Sans réseau, le vocal reste joint : il partira avec la demande.
  Future<void> _transcribe(String path) async {
    setState(() => _transcribing = true);
    final api = AppScope.api(context);

    try {
      var note = await uploadVoice(api, path, _voiceSeconds);
      _voiceNoteId = note['id'] as int;

      for (var i = 0; i < 20 && note['status'] == 'processing'; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        note = await api.get('/voice-notes/$_voiceNoteId') as Map<String, dynamic>;
      }

      final transcript = note['transcript'] as String?;
      if (mounted && note['status'] == 'done' && transcript != null && _text.text.trim().isEmpty) {
        _text.text = transcript;
      }
    } on NetworkException {
      if (mounted) showMessage(context, 'Vocal gardé. Il sera envoyé avec votre demande.');
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _transcribing = false);
    }
  }

  Future<void> _pickPoint() async {
    final point = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => MapScreen(initial: _point)),
    );
    if (point != null) setState(() => _point = point);
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    final landmark = _landmark.text.trim();

    if (text.length < 3 && _voicePath == null) {
      return showMessage(context, 'Écrivez ou dictez votre demande.');
    }
    if (landmark.isEmpty) {
      return showMessage(context, 'Indiquez un repère pour le livreur.');
    }

    setState(() => _sending = true);
    final navigator = Navigator.of(context);
    final outbox = AppScope.outbox(context);

    try {
      final sent = await outbox.submit(PendingOrder(
        clientUuid: _clientUuid,
        text: text.length < 3 ? 'Demande vocale, à écouter.' : text,
        landmark: landmark,
        lat: _point?.latitude,
        lng: _point?.longitude,
        voicePath: _voicePath,
        voiceNoteId: _voiceNoteId,
        voiceSeconds: _voiceSeconds,
      ));

      if (!mounted) return;
      showMessage(context, sent ? 'Demande envoyée.' : 'Pas de réseau : votre demande partira dès son retour.');
      navigator.pop();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle commande')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          children: [
            const Muted('Dites ou écrivez ce dont votre restaurant a besoin.'),
            const SizedBox(height: 18),
            Center(
              child: Semantics(
                button: true,
                label: _recording ? 'Arrêter l\'enregistrement' : 'Enregistrer un vocal',
                child: Material(
                  color: _recording ? p.warnBg : Palette.sky,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _transcribing ? null : _toggleRecording,
                    child: SizedBox.square(
                      dimension: 84,
                      child: Icon(_recording ? Icons.stop : Icons.mic_none, size: 36, color: _recording ? p.warn : Palette.onSky),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                _recording ? 'Enregistrement... touchez pour arrêter' : 'Touchez pour parler',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 12),
            if (_transcribing) const LinearProgressIndicator(),
            if (_voicePath != null && !_transcribing)
              const Align(alignment: Alignment.centerLeft, child: StatusBadge('Vocal joint, relisez le texte ci-dessous')),
            const SizedBox(height: 12),
            const Label('Votre demande'),
            const SizedBox(height: 8),
            TextField(
              controller: _text,
              minLines: 4,
              maxLines: 8,
              maxLength: 5000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Exemple : 20 kg de riz et 10 L d\'huile pour demain matin', counterText: ''),
            ),
            const SizedBox(height: 16),
            const Label('Repère pour le livreur'),
            const SizedBox(height: 8),
            TextField(
              controller: _landmark,
              maxLength: 255,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Exemple : face à la pharmacie du marché', counterText: ''),
            ),
            const SizedBox(height: 12),
            AppCard(
              onTap: _pickPoint,
              child: Row(
                children: [
                  const Icon(Icons.place_outlined, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Point de livraison', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        Muted(_point == null ? 'Placer sur la carte' : 'Position enregistrée', size: 13),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            BusyButton(
              label: 'Envoyer la demande',
              busy: _sending,
              onPressed: _recording || _transcribing ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}
