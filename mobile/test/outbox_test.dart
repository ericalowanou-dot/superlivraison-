import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:superlivraison/api/api_client.dart';
import 'package:superlivraison/state/outbox.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  PendingOrder order() => PendingOrder(clientUuid: 'abc', text: '20 kg de riz', landmark: 'Marché');

  test('sans réseau la demande est gardée, puis envoyée avec le même identifiant', () async {
    var online = false;
    final sent = <Map<String, dynamic>>[];
    final api = ApiClient(client: MockClient((request) async {
      if (!online) throw http.ClientException('coupure');
      sent.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('{}', 201);
    }))
      ..token = 'jeton';

    final outbox = Outbox(api);
    expect(await outbox.submit(order()), isFalse);
    expect(outbox.items, hasLength(1));

    online = true;
    await outbox.flush();

    expect(outbox.items, isEmpty);
    expect(sent.single['client_uuid'], 'abc');
    outbox.dispose();
  });

  test('la file survit à un redémarrage', () async {
    final api = ApiClient(client: MockClient((_) async => throw http.ClientException('coupure')));
    final first = Outbox(api);
    await first.submit(order());
    first.dispose();

    final second = Outbox(api);
    await second.load();
    expect(second.items.single.text, '20 kg de riz');
    second.dispose();
  });

  test('un refus définitif ne bloque pas les demandes suivantes', () async {
    var call = 0;
    var online = false;
    final api = ApiClient(client: MockClient((_) async {
      if (!online) throw http.ClientException('coupure');
      call++;
      return call == 1 ? http.Response('{"message":"Refus"}', 409) : http.Response('{}', 201);
    }))
      ..token = 'jeton';

    final outbox = Outbox(api);
    await outbox.submit(order());
    await outbox.submit(PendingOrder(clientUuid: 'def', text: 'Huile', landmark: 'Marché'));

    online = true;
    await outbox.flush();

    expect(call, 2);
    expect(outbox.items, isEmpty);
    outbox.dispose();
  });
}
