import 'package:flutter_test/flutter_test.dart';
import 'package:superlivraison/format.dart';

void main() {
  test('les montants sont groupés par milliers', () {
    expect(money(500), '500 FCFA');
    expect(money(12000), '12 000 FCFA');
    expect(money(1250000), '1 250 000 FCFA');
  });

  test('les dates récentes sont lisibles', () {
    final now = DateTime.now();
    expect(shortDate(now), startsWith("Aujourd'hui"));
    expect(shortDate(now.subtract(const Duration(days: 1))), startsWith('Hier'));
  });
}
