import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

/// Une demande prête à partir. Son identifiant évite tout doublon si l'envoi est rejoué.
class PendingOrder {
  PendingOrder({
    required this.clientUuid,
    required this.text,
    required this.landmark,
    this.lat,
    this.lng,
    this.voicePath,
    this.voiceNoteId,
    this.voiceSeconds,
  });

  PendingOrder.fromJson(Map<String, dynamic> j)
      : clientUuid = j['client_uuid'] as String,
        text = j['text'] as String,
        landmark = j['landmark'] as String,
        lat = j['lat'] as double?,
        lng = j['lng'] as double?,
        voicePath = j['voice_path'] as String?,
        voiceNoteId = j['voice_note_id'] as int?,
        voiceSeconds = j['voice_seconds'] as int?;

  final String clientUuid, text, landmark;
  final double? lat, lng;
  final String? voicePath;
  int? voiceNoteId;
  final int? voiceSeconds;

  Map<String, dynamic> toJson() => {
        'client_uuid': clientUuid,
        'text': text,
        'landmark': landmark,
        'lat': lat,
        'lng': lng,
        'voice_path': voicePath,
        'voice_note_id': voiceNoteId,
        'voice_seconds': voiceSeconds,
      };
}

/// Garde les demandes sur le téléphone tant que le réseau ne permet pas de les envoyer (T3).
class Outbox extends ChangeNotifier {
  Outbox(this.api);

  static const _key = 'outbox';
  static const _retryEvery = Duration(seconds: 30);

  final ApiClient api;

  final List<PendingOrder> items = [];
  Timer? _timer;
  bool _flushing = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null) {
      items.addAll((jsonDecode(saved) as List).map((e) => PendingOrder.fromJson(e as Map<String, dynamic>)));
    }
    _schedule();
  }

  /// Envoie la demande, ou la garde pour plus tard si le réseau manque.
  /// Retourne true si elle est partie tout de suite.
  Future<bool> submit(PendingOrder order) async {
    try {
      await _send(order);
      notifyListeners();
      return true;
    } on NetworkException {
      items.add(order);
      await _save();
      _schedule();
      notifyListeners();
      return false;
    }
  }

  Future<void> flush() async {
    if (_flushing || api.token == null) return;
    _flushing = true;

    try {
      for (final order in List.of(items)) {
        try {
          await _send(order);
          items.remove(order);
          await _save();
          notifyListeners();
        } on NetworkException {
          break;
        } on ApiException catch (e) {
          // Refus définitif : on retire la demande pour ne pas bloquer les suivantes.
          if (e.status != 401 && e.status != 429) {
            items.remove(order);
            await _save();
            notifyListeners();
          }
        }
      }
    } finally {
      _flushing = false;
      _schedule();
    }
  }

  Future<void> _send(PendingOrder order) async {
    if (order.voicePath != null && order.voiceNoteId == null) {
      final note = await uploadVoice(api, order.voicePath!, order.voiceSeconds);
      order.voiceNoteId = note['id'] as int;
      await _save();
    }

    await api.post('/orders', {
      'client_uuid': order.clientUuid,
      'request_text': order.text,
      'delivery_landmark': order.landmark,
      'delivery_lat': order.lat,
      'delivery_lng': order.lng,
      'voice_note_id': order.voiceNoteId,
    });
  }

  void _schedule() {
    _timer?.cancel();
    if (items.isNotEmpty) _timer = Timer(_retryEvery, flush);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

Future<Map<String, dynamic>> uploadVoice(ApiClient api, String path, int? seconds) async {
  final data = await api.upload(
    '/voice-notes',
    'audio',
    path,
    kIsWeb ? 'vocal.wav' : 'vocal.m4a',
    {if (seconds != null) 'duration_seconds': '$seconds'},
  );

  return data as Map<String, dynamic>;
}
