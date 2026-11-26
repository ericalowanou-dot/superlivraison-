import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:superlivraison/screens/otp_screen.dart';
import 'package:superlivraison/theme.dart';

void main() {
  testWidgets('l\'écran du code ne déborde pas quand le clavier est ouvert', (tester) async {
    // Téléphone courant avec le clavier ouvert : il ne reste qu'un tiers de la hauteur.
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    tester.view.viewInsets = const FakeViewPadding(bottom: 1000);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const OtpScreen(phone: '+22890000000'),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);

    // Le bouton reste accessible en faisant défiler.
    await tester.scrollUntilVisible(find.text('Continuer'), 100, scrollable: find.byType(Scrollable).first);
    expect(find.text('Continuer'), findsOneWidget);
  });
}
