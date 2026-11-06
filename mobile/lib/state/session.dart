import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../models.dart';
import 'outbox.dart';

class Session extends ChangeNotifier {
  Session(this.api) {
    api.onUnauthorized = _clear;
  }

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'token';
  static const _themeKey = 'theme';

  final ApiClient api;

  AppUser? user;
  ThemeMode themeMode = ThemeMode.system;

  /// Restaure la session. Sans réseau, l'utilisateur reste connecté et réessaie plus tard.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values.asNameMap()[prefs.getString(_themeKey)] ?? ThemeMode.system;

    api.token = await _storage.read(key: _tokenKey);
    if (api.token == null) return;

    try {
      await refreshUser();
    } on NetworkException {
      offline = true;
    } on ApiException {
      await _clear();
    }
  }

  /// Le serveur n'a pas pu être joint au démarrage.
  bool offline = false;

  Future<void> refreshUser() async {
    user = AppUser.fromJson(await api.get('/me') as Map<String, dynamic>);
    offline = false;
    notifyListeners();
  }

  Future<void> requestCode(String phone) => api.post('/auth/request-code', {'phone': phone});

  Future<void> verifyCode(String phone, String code) async {
    final data = await api.post('/auth/verify-code', {
      'phone': phone,
      'code': code,
      'device_name': 'application-mobile',
    }) as Map<String, dynamic>;

    api.token = data['token'] as String;
    await _storage.write(key: _tokenKey, value: api.token);
    user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    notifyListeners();
  }

  Future<void> updateProfile(Map<String, dynamic> changes) async {
    user = AppUser.fromJson(await api.patch('/me', changes) as Map<String, dynamic>);
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  }

  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } on Exception {
      // Le jeton local est supprimé même si le serveur est injoignable.
    }
    await _clear();
  }

  Future<void> deleteAccount() async {
    await api.delete('/me');
    await _clear();
  }

  Future<void> _clear() async {
    api.token = null;
    user = null;
    await _storage.delete(key: _tokenKey);
    notifyListeners();
  }
}

/// Donne accès à la session et à la file d'envoi depuis tous les écrans.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required Session session, required Outbox outbox, required super.child})
      : _session = session,
        _outbox = outbox;

  final Session _session;
  final Outbox _outbox;

  // Lecture simple, sans abonnement : possible dès initState, et ces objets ne changent jamais.
  static AppScope _of(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!;

  static Session session(BuildContext context) => _of(context)._session;

  static Outbox outbox(BuildContext context) => _of(context)._outbox;

  static ApiClient api(BuildContext context) => _of(context)._session.api;

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
