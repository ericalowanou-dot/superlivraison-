import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:superlivraison/api/api_client.dart';
import 'package:superlivraison/main.dart';
import 'package:superlivraison/state/outbox.dart';
import 'package:superlivraison/state/session.dart';

Map<String, dynamic> userJson({bool setup = true, String role = 'restaurant'}) => {
      'id': 1,
      'phone': '+22890000000',
      'name': null,
      'business_name': null,
      'role': role,
      'language_code': 'fr',
      'city': setup ? null : {'id': 1, 'name': 'Lomé', 'country_id': 1},
      'needs_setup': setup,
    };

Map<String, dynamic> orderJson({String status = 'price_pending', String label = 'Prix à valider', String? mode}) => {
      'id': 7,
      'reference': 'CMD-1007',
      'channel': 'text',
      'request_text': '20 kg de riz',
      'has_voice': false,
      'delivery': {'lat': null, 'lng': null, 'landmark': 'Marché'},
      'status': status,
      'status_label': label,
      'price': 12000,
      'currency': 'XOF',
      'payment_mode': mode,
      'is_paid': false,
      'cancel_reason': null,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'events': <Object>[],
    };

Map<String, dynamic> paymentJson(String status, String label) => {
      'id': 3,
      'order_id': 7,
      'order_reference': 'CMD-1007',
      'amount': 12000,
      'currency': 'XOF',
      'method': 'flooz',
      'method_label': 'Flooz',
      'status': status,
      'status_label': label,
      'failure_reason': null,
      'paid_at': null,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

/// Faux serveur : répond comme l'API et garde la trace des requêtes.
class FakeServer {
  final calls = <String, Map<String, dynamic>>{};
  var orderStatus = 'price_pending';
  var paymentChecks = 0;

  http.Response _ok(Object body, [int status = 200]) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json'},
      );

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path.replaceFirst('/api/v1', '');
    calls[path] = request.body.isEmpty ? {} : jsonDecode(request.body) as Map<String, dynamic>;

    switch (path) {
      case '/auth/request-code':
        return _ok({'message': 'ok'}, 202);
      case '/auth/verify-code':
      case '/auth/login':
        return _ok({'token': '1|jeton', 'user': userJson()});
      case '/auth/register':
        return _ok({'token': '1|jeton', 'user': userJson()}, 201);
      case '/reference':
        return _ok({
          'languages': [
            {'code': 'fr', 'name': 'Français'},
          ],
          'countries': [
            {
              'id': 1,
              'name': 'Togo',
              'code': 'TG',
              'dial_code': '+228',
              'currency': 'XOF',
              'cities': [
                {'id': 1, 'country_id': 1, 'name': 'Lomé'},
              ],
            },
          ],
        });
      case '/me':
        return _ok(userJson(setup: false));
      case '/orders':
        return _ok({
          'data': [orderJson()],
          'meta': {'current_page': 1, 'last_page': 1},
        });
      case '/payments':
        return _ok({
          'data': <Object>[],
          'meta': {'current_page': 1, 'last_page': 1},
        });
      case '/ads':
      case '/ads/mine':
      case '/shops':
        return _ok({
          'data': <Object>[],
          'meta': {'current_page': 1, 'last_page': 1},
        });
      case '/courier-requests':
        return _ok(orderJson(), 201);
      case '/orders/7':
        return _ok(orderJson());
      case '/orders/7/accept-price':
        return _ok(orderJson(status: 'confirmed', label: 'Confirmée'));
      case '/orders/7/payments':
        return _ok(paymentJson('pending', 'En attente'), 201);
      case '/payments/3':
        paymentChecks++;
        return _ok(paymentJson('succeeded', 'Réussi'));
    }

    return _ok({'message': 'Route inconnue : $path'}, 404);
  }
}

void main() {
  late FakeServer server;

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    server = FakeServer();
    final api = ApiClient(client: MockClient(server.handle));
    await tester.pumpWidget(App(session: Session(api), outbox: Outbox(api)));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester) async {
    expect(find.text('Tout ce dont vous avez besoin, livré chez vous'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'ama@exemple.tg');
    await tester.enterText(find.byType(TextField).at(1), 'motdepasse');
    await tap(tester, 'Se connecter');
    expect(server.calls['/auth/login'], {'email': 'ama@exemple.tg', 'password': 'motdepasse', 'device_name': 'application-mobile'});
    expect(find.text('Où êtes-vous ?'), findsOneWidget);

    await tap(tester, 'Commencer');
    expect(find.text('Téléphone du destinataire'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));

    await tap(tester, 'Commandes');
    expect(find.text('Mes commandes'), findsOneWidget);
    expect(server.calls['/me'], {'language_code': 'fr', 'city_id': 1});
  }

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('du premier lancement au paiement à la livraison', (tester) async {
    await pumpApp(tester);
    await signIn(tester);

    await tap(tester, 'CMD-1007');
    expect(find.text('12 000 FCFA'), findsOneWidget);

    await tap(tester, 'Accepter et payer');
    await tap(tester, 'Payer à la livraison');
    await tap(tester, 'Confirmer');

    expect(find.text('Commande confirmée'), findsOneWidget);
    expect(server.calls['/orders/7/accept-price'], {'payment_mode': 'cash', 'price': 12000});
    expect(server.calls.containsKey('/orders/7/payments'), isFalse);

    await tap(tester, 'Suivre ma commande');
    await tester.pageBack();
    await tester.pumpAndSettle();
  });

  testWidgets('un nouvel utilisateur crée son compte puis choisit sa ville', (tester) async {
    await pumpApp(tester);
    await tap(tester, 'Créer un compte');

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Ama Mensah');
    await tester.enterText(fields.at(1), 'ama@exemple.tg');
    await tester.enterText(fields.at(3), 'motdepasse');
    await tester.enterText(fields.at(4), 'autrechose');
    await tap(tester, 'Créer mon compte');
    expect(find.text('Les deux mots de passe ne sont pas identiques.'), findsOneWidget);
    expect(server.calls.containsKey('/auth/register'), isFalse);

    await tester.enterText(fields.at(4), 'motdepasse');
    await tap(tester, 'Créer mon compte');
    // Le préfixe +228 seul ne compte pas comme un numéro.
    expect(server.calls['/auth/register'], {
      'name': 'Ama Mensah',
      'email': 'ama@exemple.tg',
      'password': 'motdepasse',
      'password_confirmation': 'motdepasse',
      'device_name': 'application-mobile',
    });
    expect(find.text('Où êtes-vous ?'), findsOneWidget);
  });

  testWidgets('le paiement mobile attend la confirmation du serveur', (tester) async {
    await pumpApp(tester);
    await signIn(tester);

    await tap(tester, 'CMD-1007');
    await tap(tester, 'Accepter et payer');
    await tap(tester, 'Flooz');

    await tester.ensureVisible(find.text('Confirmer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Paiement réussi'), findsNothing);
    expect(find.text('Validez le paiement sur votre téléphone.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('Paiement réussi'), findsOneWidget);
    expect(server.calls['/orders/7/accept-price'], {'payment_mode': 'mobile_money', 'price': 12000});
    expect(server.calls['/orders/7/payments']?['method'], 'flooz');
    expect(server.paymentChecks, 1);

    await tap(tester, 'Suivre ma commande');
    await tester.pageBack();
    await tester.pumpAndSettle();
  });
}
