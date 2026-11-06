import 'package:flutter/foundation.dart';

import '../models.dart';

class CartLine {
  CartLine(this.product, this.quantity);

  final Product product;
  int quantity;

  int get subtotal => product.price * quantity;
}

/// Le panier ne contient que les articles d'une seule boutique.
class Cart extends ChangeNotifier {
  static const maxQuantity = 99;

  Shop? _shop;
  final Map<int, CartLine> _lines = {};

  Shop? get shop => _shop;
  List<CartLine> get lines => _lines.values.toList();
  bool get isEmpty => _lines.isEmpty;
  int get count => _lines.values.fold(0, (sum, line) => sum + line.quantity);
  int get total => _lines.values.fold(0, (sum, line) => sum + line.subtotal);

  int quantityOf(Product product) => _lines[product.id]?.quantity ?? 0;

  bool belongsToAnotherShop(Shop shop) => _shop != null && _shop!.id != shop.id && !isEmpty;

  bool canAdd(Product product) {
    final next = quantityOf(product) + 1;
    return next <= maxQuantity && (product.stock == null || next <= product.stock!);
  }

  void add(Shop shop, Product product) {
    if (belongsToAnotherShop(shop)) clear();
    if (!canAdd(product)) return;

    _shop = shop;
    _lines.update(product.id, (line) => line..quantity += 1, ifAbsent: () => CartLine(product, 1));
    notifyListeners();
  }

  void remove(Product product) {
    final line = _lines[product.id];
    if (line == null) return;

    line.quantity -= 1;
    if (line.quantity == 0) _lines.remove(product.id);
    if (_lines.isEmpty) _shop = null;
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    _shop = null;
    notifyListeners();
  }
}
