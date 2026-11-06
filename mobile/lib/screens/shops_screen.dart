import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../state/cart.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'my_shop_screen.dart';
import 'shop_screen.dart';

/// Les boutiques de la ville, et l'accès à sa propre boutique.
class ShopsScreen extends StatefulWidget {
  const ShopsScreen({super.key});

  @override
  State<ShopsScreen> createState() => _ShopsScreenState();
}

class _ShopsScreenState extends State<ShopsScreen> {
  // Le panier survit au passage d'une boutique à l'autre, et d'un onglet à l'autre.
  final _cart = Cart();
  final List<Shop> _shops = [];
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  Object? _error;
  String _search = '';
  Timer? _debounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _shops.isEmpty && _error == null) _fetch(1);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cart.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search = value.trim();
      _fetch(1);
    });
  }

  Future<void> _fetch(int page) async {
    final search = _search;

    try {
      final query = 'page=$page&search=${Uri.encodeQueryComponent(search)}';
      final data = await AppScope.api(context).get('/shops?$query') as Map<String, dynamic>;
      final items = (data['data'] as List).map((s) => Shop.fromJson(s as Map<String, dynamic>));
      final meta = data['meta'] as Map<String, dynamic>;

      // Une recherche plus récente est partie entre-temps : on ignore celle-ci.
      if (!mounted || search != _search) return;
      setState(() {
        if (page == 1) _shops.clear();
        _shops.addAll(items);
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

  Future<void> _open(Shop shop) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopScreen(shop: shop, cart: _cart)));
    await _fetch(1);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: () => _fetch(1),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.add_business_outlined, size: 20),
            label: const Text('Ma boutique'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyShopScreen())),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: _onSearch,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(hintText: 'Rechercher une boutique', prefixIcon: Icon(Icons.search)),
          ),
          const SizedBox(height: 16),
          ListenableBuilder(
            listenable: _cart,
            builder: (context, _) {
              final shop = _cart.shop;
              if (shop == null) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  color: Palette.of(context).soft,
                  onTap: () => _open(shop),
                  child: Row(
                    children: [
                      const Icon(Icons.shopping_cart_outlined, size: 22),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Panier en cours chez ${shop.name}', style: const TextStyle(fontWeight: FontWeight.w700))),
                    ],
                  ),
                ),
              );
            },
          ),
          if (_error != null && _shops.isEmpty)
            ErrorRetry(error: _error!, onRetry: () => _fetch(1))
          else if (_shops.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Muted(
                _search.isEmpty ? 'Aucune boutique dans votre ville pour le moment.' : 'Aucune boutique ne correspond.',
                align: TextAlign.center,
              ),
            ),
          for (final shop in _shops)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                onTap: () => _open(shop),
                child: Row(
                  children: [
                    ShopThumbnail(shop: shop),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(shop.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          if (shop.category != null) Muted(shop.category!, size: 13),
                          if (shop.landmark != null) Muted(shop.landmark!, size: 12),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          if (_hasMore) OutlinedButton(onPressed: () => _fetch(_page + 1), child: const Text('Voir plus')),
        ],
      ),
    );
  }
}

class ShopThumbnail extends StatelessWidget {
  const ShopThumbnail({super.key, required this.shop, this.size = 60});

  final Shop shop;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: shop.hasImage
          ? AuthImage(shop.imagePath, width: size, height: size)
          : ColoredBox(
              color: Palette.of(context).soft,
              child: SizedBox.square(dimension: size, child: const Icon(Icons.storefront_outlined)),
            ),
    );
  }
}
