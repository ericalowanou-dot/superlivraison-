import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:superlivraison/api/api_client.dart';
import 'package:superlivraison/state/push.dart';

void main() {
  test('une notification de message ouvre la discussion de la course', () {
    final target = PushTarget.fromData({'kind': 'message', 'order_id': '12', 'reference': 'CMD-1012'}, title: 'Kodjo', body: 'Je suis là');

    expect(target.isMessage, isTrue);
    expect(target.orderId, 12);
    expect(target.reference, 'CMD-1012');
  });

  test('une notification sans type concerne la commande', () {
    final target = PushTarget.fromData({'order_id': '5'});

    expect(target.isMessage, isFalse);
    expect(target.orderId, 5);
  });

  test('sans réglages Firebase, les notifications restent éteintes sans gêner l\'application', () async {
    var calls = 0;
    final api = ApiClient(client: MockClient((_) async {
      calls++;
      return http.Response('', 204);
    }))
      ..token = 'jeton';
    final push = Push(api);

    await push.init();
    await push.register();

    expect(push.token, isNull);
    expect(calls, 0);
  });
}
