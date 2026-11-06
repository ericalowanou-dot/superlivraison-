import 'package:flutter_test/flutter_test.dart';
import 'package:superlivraison/models.dart';
import 'package:superlivraison/state/cart.dart';

Shop shop(int id) => Shop.fromJson({
      'id': id,
      'name': 'Boutique $id',
      'has_image': false,
      'status': 'approved',
      'status_label': 'Publiée',
    });

Product product(int id, {int price = 1000, int? stock}) => Product.fromJson({
      'id': id,
      'shop_id': 1,
      'name': 'Article $id',
      'price': price,
      'stock': stock,
      'is_active': true,
    });

void main() {
  test('le panier additionne les quantités et les prix', () {
    final cart = Cart();
    final rice = product(1, price: 4000);

    cart.add(shop(1), rice);
    cart.add(shop(1), rice);
    cart.add(shop(1), product(2, price: 1500));

    expect(cart.count, 3);
    expect(cart.total, 9500);
    expect(cart.quantityOf(rice), 2);
  });

  test('le stock limite les quantités', () {
    final cart = Cart();
    final rice = product(1, stock: 2);

    cart
      ..add(shop(1), rice)
      ..add(shop(1), rice)
      ..add(shop(1), rice);

    expect(cart.quantityOf(rice), 2);
    expect(cart.canAdd(rice), isFalse);
  });

  test('un article en rupture ne peut pas être ajouté', () {
    final soldOut = product(1, stock: 0);

    expect(soldOut.isSoldOut, isTrue);
    expect(Cart().canAdd(soldOut), isFalse);
  });

  test('une autre boutique remplace le panier', () {
    final cart = Cart();
    cart.add(shop(1), product(1));

    expect(cart.belongsToAnotherShop(shop(2)), isTrue);

    cart.add(shop(2), product(2));

    expect(cart.shop?.id, 2);
    expect(cart.count, 1);
  });

  test('retirer le dernier article libère la boutique', () {
    final cart = Cart();
    final rice = product(1);

    cart.add(shop(1), rice);
    cart.remove(rice);

    expect(cart.isEmpty, isTrue);
    expect(cart.shop, isNull);
    expect(cart.belongsToAnotherShop(shop(2)), isFalse);
  });
}
