import 'package:flutter_test/flutter_test.dart';
import 'package:superlivraison/models.dart';

Map<String, dynamic> orderJson(Map<String, dynamic> extra) => {
      'id': 1,
      'reference': 'CMD-1001',
      'request_text': '20 kg de riz',
      'has_voice': false,
      'delivery': {'lat': null, 'lng': null, 'landmark': 'Marché'},
      'status': 'received',
      'status_label': 'Reçue',
      'price': null,
      'payment_mode': null,
      'is_paid': false,
      'cancel_reason': null,
      'created_at': '2026-11-05T10:00:00.000000Z',
      ...extra,
    };

void main() {
  test('une commande reçue peut être annulée mais pas payée', () {
    final order = Order.fromJson(orderJson({}));
    expect(order.canCancel, isTrue);
    expect(order.awaitsPrice, isFalse);
    expect(order.awaitsMobilePayment, isFalse);
  });

  test('un paiement mobile non réglé reste à payer', () {
    final order = Order.fromJson(orderJson({'status': 'confirmed', 'payment_mode': 'mobile_money', 'price': 5000}));
    expect(order.awaitsMobilePayment, isTrue);
    expect(order.canCancel, isFalse);
  });

  test('une commande payée ou à la livraison ne demande plus de paiement', () {
    expect(Order.fromJson(orderJson({'status': 'confirmed', 'payment_mode': 'mobile_money', 'is_paid': true})).awaitsMobilePayment, isFalse);
    expect(Order.fromJson(orderJson({'status': 'confirmed', 'payment_mode': 'cash'})).awaitsMobilePayment, isFalse);
  });

  test('un compte sans ville passe par la configuration', () {
    final user = AppUser.fromJson({
      'id': 1,
      'phone': '+22890000000',
      'name': null,
      'business_name': null,
      'role': 'restaurant',
      'language_code': 'fr',
      'needs_setup': true,
    });
    expect(user.needsSetup, isTrue);
    expect(user.isCourier, isFalse);
    expect(user.cityId, isNull);
  });
}
