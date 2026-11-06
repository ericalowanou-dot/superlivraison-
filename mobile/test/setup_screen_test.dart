import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:superlivraison/api/api_client.dart';
import 'package:superlivraison/screens/setup_screen.dart';
import 'package:superlivraison/state/outbox.dart';
import 'package:superlivraison/state/session.dart';
import 'package:superlivraison/theme.dart';

void main() {
  Map<String, dynamic> country(int id, String name, String code, List<String> cities) => {
        'id': id,
        'name': name,
        'code': code,
        'dial_code': '+228',
        'currency': 'XOF',
        'cities': [
          for (final (i, city) in cities.indexed) {'id': id * 100 + i, 'country_id': id, 'name': city},
        ],
      };

  http.Response json(Object body) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        200,
        headers: {'content-type': 'application/json'},
      );

  Future<void> pump(WidgetTester tester, List<Map<String, dynamic>> countries, {ThemeData? theme}) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = ApiClient(client: MockClient((_) async => json({
          'languages': [
            {'code': 'fr', 'name': 'Français'},
          ],
          'countries': countries,
        })));

    await tester.pumpWidget(AppScope(
      session: Session(api),
      outbox: Outbox(api),
      child: MaterialApp(theme: theme ?? AppTheme.light, home: const SetupScreen()),
    ));
    await tester.pumpAndSettle();
  }

  FilledButton startButton(WidgetTester tester) => tester.widget(find.byType(FilledButton));

  testWidgets('une seule ville est choisie d\'office', (tester) async {
    await pump(tester, [country(1, 'Togo', 'TG', ['Lomé'])]);

    expect(find.text('🇹🇬'), findsOneWidget);
    expect(startButton(tester).onPressed, isNotNull);
  });

  testWidgets('le bouton attend le choix de la ville', (tester) async {
    await pump(tester, [country(1, 'Togo', 'TG', ['Lomé', 'Kara'])]);
    expect(startButton(tester).onPressed, isNull);

    await tester.ensureVisible(find.text('Kara'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kara'));
    await tester.pump();
    expect(startButton(tester).onPressed, isNotNull);
  });

  testWidgets('changer de pays efface la ville choisie', (tester) async {
    await pump(tester, [
      country(1, 'Togo', 'TG', ['Lomé', 'Kara']),
      country(2, 'Bénin', 'BJ', ['Cotonou', 'Parakou']),
    ]);

    await tester.tap(find.text('Togo'));
    await tester.pump();
    await tester.ensureVisible(find.text('Kara'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kara'));
    await tester.pump();
    expect(startButton(tester).onPressed, isNotNull);

    await tester.ensureVisible(find.text('Bénin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bénin'));
    await tester.pump();

    expect(find.text('Kara'), findsNothing);
    expect(find.text('Cotonou'), findsOneWidget);
    expect(startButton(tester).onPressed, isNull);
  });

  testWidgets('une longue liste de villes propose une recherche', (tester) async {
    await pump(tester, [
      country(1, 'Togo', 'TG', ['Lomé', 'Kara', 'Sokodé', 'Atakpamé', 'Kpalimé', 'Dapaong', 'Tsévié']),
    ]);

    await tester.enterText(find.byType(TextField), 'kar');
    await tester.pump();

    expect(find.text('Kara'), findsOneWidget);
    expect(find.text('Lomé'), findsNothing);
  });

  testWidgets('la page tient sur un petit écran en thème sombre', (tester) async {
    await pump(tester, [country(1, 'Togo', 'TG', ['Lomé'])], theme: AppTheme.dark);
    tester.view.physicalSize = const Size(320, 568);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Commencer'), findsOneWidget);
  });
}
