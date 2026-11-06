import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:superlivraison/api/api_client.dart';

void main() {
  ApiClient client(http.Response response) => ApiClient(client: MockClient((_) async => response));

  http.Response json(Object body, int status) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json'},
      );

  test('une erreur de validation affiche le premier message', () async {
    final api = client(json({
      'message': 'x',
      'errors': {
        'phone': ['Ce numéro de téléphone est invalide.'],
      },
    }, 422));

    expect(
      () => api.post('/auth/request-code'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Ce numéro de téléphone est invalide.')),
    );
  });

  test('un refus métier affiche le message du serveur', () async {
    final api = client(json({'message': 'Le prix a changé. Vérifiez le nouveau montant.'}, 409));

    expect(
      () => api.post('/orders/1/accept-price'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 409)),
    );
  });

  test('une erreur serveur ne montre pas de détail technique', () async {
    final api = client(json({'message': 'SQLSTATE[42000]'}, 500));

    expect(
      () => api.get('/orders'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Une erreur est survenue. Réessayez.')),
    );
  });

  test('un jeton expiré prévient la session', () async {
    var called = false;
    final api = client(json({'message': 'Unauthenticated.'}, 401))..onUnauthorized = () => called = true;

    await expectLater(api.get('/me'), throwsA(isA<ApiException>()));
    expect(called, isTrue);
  });

  test('une coupure réseau est reconnue', () async {
    final api = ApiClient(client: MockClient((_) async => throw http.ClientException('coupure')));

    await expectLater(api.get('/orders'), throwsA(isA<NetworkException>()));
  });

  test('les accents sont lus correctement', () async {
    final api = client(json({'name': 'Lomé'}, 200));

    expect(await api.get('/x'), {'name': 'Lomé'});
  });
}
