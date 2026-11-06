import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Le serveur a répondu par un refus. [message] s'affiche tel quel.
class ApiException implements Exception {
  ApiException(this.message, this.status);

  final String message;
  final int status;

  @override
  String toString() => message;
}

/// Pas de réseau ou serveur injoignable : l'action peut être relancée.
class NetworkException implements Exception {
  @override
  String toString() => 'Connexion impossible. Vérifiez votre réseau.';
}

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  static const baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: kIsWeb ? 'http://localhost:8000/api/v1' : 'http://10.0.2.2:8000/api/v1',
  );

  final http.Client _client;

  String? token;

  /// Appelé quand le jeton n'est plus valide.
  VoidCallback? onUnauthorized;

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// Pour charger une image protégée par le jeton de connexion.
  String url(String path) => '$baseUrl$path';

  Map<String, String> get authHeaders => _headers;

  Future<dynamic> get(String path) => _send(() => _client.get(_uri(path), headers: _headers));

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) => _send(
        () => _client.post(_uri(path), headers: _json, body: jsonEncode(body ?? const {})),
      );

  Future<dynamic> patch(String path, Map<String, dynamic> body) => _send(
        () => _client.patch(_uri(path), headers: _json, body: jsonEncode(body)),
      );

  Future<dynamic> delete(String path) => _send(() => _client.delete(_uri(path), headers: _headers));

  Future<Uint8List> download(String path) async {
    final response = await _guard(() => _client.get(_uri(path), headers: _headers));
    if (response.statusCode >= 400) _throw(response);
    return response.bodyBytes;
  }

  Future<dynamic> upload(String path, String field, String filePath, String filename, Map<String, String> fields) {
    return _send(() async {
      final request = http.MultipartRequest('POST', _uri(path))
        ..headers.addAll(_headers)
        ..fields.addAll(fields)
        ..files.add(http.MultipartFile.fromBytes(field, await _readFile(filePath), filename: filename));

      return http.Response.fromStream(await _client.send(request));
    }, timeout: const Duration(seconds: 90));
  }

  /// Sur le web, l'enregistrement est une adresse en mémoire du navigateur.
  Future<Uint8List> _readFile(String path) async =>
      kIsWeb ? (await _client.get(Uri.parse(path))).bodyBytes : File(path).readAsBytes();

  Map<String, String> get _json => {..._headers, 'Content-Type': 'application/json'};

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<dynamic> _send(Future<http.Response> Function() call, {Duration timeout = const Duration(seconds: 20)}) async {
    final response = await _guard(call, timeout: timeout);
    if (response.statusCode >= 400) _throw(response);
    if (response.body.isEmpty) return null;
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<http.Response> _guard(Future<http.Response> Function() call, {Duration timeout = const Duration(seconds: 20)}) async {
    try {
      return await call().timeout(timeout);
    } on TimeoutException {
      throw NetworkException();
    } on http.ClientException {
      throw NetworkException();
    }
  }

  Never _throw(http.Response response) {
    if (response.statusCode == 401) onUnauthorized?.call();
    if (response.statusCode == 429) {
      throw ApiException('Trop de tentatives. Patientez un instant.', 429);
    }

    var message = 'Une erreur est survenue. Réessayez.';
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final errors = body['errors'];
      if (errors is Map && errors.isNotEmpty) {
        message = (errors.values.first as List).first as String;
      } else if (response.statusCode < 500 && body['message'] is String) {
        message = body['message'] as String;
      }
    } on FormatException {
      // Réponse non JSON : on garde le message général.
    }

    throw ApiException(message, response.statusCode);
  }
}
