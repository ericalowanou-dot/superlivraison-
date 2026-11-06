import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../state/cart.dart';
import '../state/session.dart';
import '../widgets.dart';
import 'cart_screen.dart';
import 'shops_screen.dart';

/// Une boutique : ses articles, avec ajout au panier.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, required this.shop, required this.cart});

  final Shop shop;
  final Cart cart;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final List<Product> _products = [];
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  Object? _error;

  Shop get _shop => widget.shop;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _products.isEmpty && _error == null) _fetch(1);
  }

  Future<void> _fetch(int page) async {
    try {
      final data = await AppScope.api(context).get('/shops/${_shop.id}/products?page=$page') as Map<String, dynamic>;
      final items = (data['data'] as List).map((p) => Product.fromJson(p as Map<String, dynamic>));
      final meta = data['meta'] as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        if (page == 1) _products.clear();
        _products.addAll(items);
        _page = page;
        _hasMore = (meta['current_page'] as int) < (meta['last_page'] as int);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add(Product product) async {
    if (widget.cart.belongsToAnotherShop(_shop)) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Vider le panier ?'),
          content: Text('Votre panier contient des articles de ${widget.cart.shop!.name}. Un panier ne peut contenir qu\'une seule boutique.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Garder')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Vider et ajouter')),
          ],
        ),
      );
      if (replace != true) return;
    }

    widget.cart.add(_shop, product);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_shop.name)),
      bottomNavigationBar: ListenableBuilder(
        listenable: widget.cart,
        builder: (context, _) {
          final cart = widget.cart;
          if (cart.isEmpty || cart.shop?.id != _shop.id) return const SizedBox.shrink();

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: BusyButton(
                label: 'Panier (${cart.count}) · ${money(cart.total)}',
                icon: Icons.shopping_cart_outlined,
                busy: false,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CartScreen(cart: cart))),
              ),
            ),
          );
        },
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _products.isEmpty
                ? ErrorRetry(error: _error!, onRetry: () => _fetch(1))
                : RefreshIndicator(
                    onRefresh: () => _fetch(1),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      children: [
                        _header(),
                        const SizedBox(height: 20),
                        const Label('Articles'),
                        const SizedBox(height: 12),
                        if (_products.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Muted('Cette boutique n\'a pas encore d\'article.', align: TextAlign.center),
                          ),
                        for (final product in _products)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _ProductCard(product: product, cart: widget.cart, readOnly: _shop.isMine, onAdd: () => _add(product)),
                          ),
                        if (_hasMore) OutlinedButton(onPressed: () => _fetch(_page + 1), child: const Text('Voir plus')),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ShopThumbnail(shop: _shop, size: 72),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Heading(_shop.name, size: 20),
                  if (_shop.category != null) Muted(_shop.category!, size: 13),
                  if (_shop.landmark != null) Muted(_shop.landmark!, size: 13),
                ],
              ),
            ),
          ],
        ),
        if (_shop.description != null) ...[
          const SizedBox(height: 12),
          Text(_shop.description!, style: const TextStyle(fontSize: 14)),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            if (_shop.phone != null)
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('Appeler'),
                  onPressed: () => callPhone(context, _shop.phone!),
                ),
              ),
            if (_shop.phone != null && _shop.lat != null) const SizedBox(width: 8),
            if (_shop.lat != null && _shop.lng != null)
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.place_outlined, size: 18),
                  label: const Text('Carte'),
                  onPressed: () => openMap(context, _shop.lat!, _shop.lng!),
                ),
              ),
          ],
        ),
        if (_shop.isMine) ...[
          const SizedBox(height: 12),
          const Muted('C\'est votre boutique : vous voyez ce que voient vos clients.', size: 13),
        ],
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.cart, required this.readOnly, required this.onAdd});

  final Product product;
  final Cart cart;
  final bool readOnly;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AuthImage(product.imagePath, width: 96, height: 96),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                if (product.description != null) ...[
                  const SizedBox(height: 2),
                  Muted(product.description!, size: 13),
                ],
                const SizedBox(height: 6),
                Text(money(product.price), style: const TextStyle(fontWeight: FontWeight.w800)),
                if (product.isSoldOut) const Muted('Rupture de stock', size: 12),
                if (!readOnly && !product.isSoldOut) ...[
                  const SizedBox(height: 6),
                  ListenableBuilder(
                    listenable: cart,
                    builder: (context, _) {
                      final quantity = cart.quantityOf(product);
                      if (quantity == 0) {
                        return SizedBox(
                          height: 40,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.add_shopping_cart, size: 18),
                            label: const Text('Ajouter'),
                            onPressed: onAdd,
                          ),
                        );
                      }

                      return QuantityStepper(
                        quantity: quantity,
                        onRemove: () => cart.remove(product),
                        onAdd: cart.canAdd(product) ? onAdd : null,
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class QuantityStepper extends StatelessWidget {
  const QuantityStepper({super.key, required this.quantity, required this.onRemove, required this.onAdd});

  final int quantity;
  final VoidCallback onRemove;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(tooltip: 'Retirer', icon: const Icon(Icons.remove, size: 18), onPressed: onRemove),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text('$quantity', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        IconButton.outlined(tooltip: 'Ajouter', icon: const Icon(Icons.add, size: 18), onPressed: onAdd),
      ],
    );
  }
}
