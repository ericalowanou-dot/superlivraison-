import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'product_form_screen.dart';
import 'seller_screens.dart';
import 'shop_form_screen.dart';

/// Espace vendeur : création de la boutique, articles, commandes et gains.
class MyShopScreen extends StatefulWidget {
  const MyShopScreen({super.key});

  @override
  State<MyShopScreen> createState() => _MyShopScreenState();
}

class _MyShopScreenState extends State<MyShopScreen> {
  Shop? _shop;
  List<Product> _products = [];
  bool _loading = true;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _shop == null && _error == null) _fetch();
  }

  Future<void> _fetch() async {
    final api = AppScope.api(context);

    try {
      final data = await api.get('/my-shop') as Map<String, dynamic>;
      final json = data['shop'] as Map<String, dynamic>?;
      final products = json == null ? null : await api.get('/my-shop/products') as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _shop = json == null ? null : Shop.fromJson(json);
        _products = ((products?['data'] as List?) ?? const []).map((p) => Product.fromJson(p as Map<String, dynamic>)).toList();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ma boutique')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _shop == null
                ? ErrorRetry(error: _error!, onRetry: _fetch)
                : RefreshIndicator(onRefresh: _fetch, child: _shop == null ? _intro() : _dashboard(_shop!)),
      ),
    );
  }

  Widget _intro() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.storefront_outlined, size: 56),
        const SizedBox(height: 16),
        const Heading('Vendez sur Superlivraison', size: 22),
        const SizedBox(height: 8),
        const Muted('Créez votre boutique, ajoutez vos articles, et nous livrons vos clients. Votre boutique sera visible après validation par notre équipe.'),
        const SizedBox(height: 20),
        BusyButton(label: 'Créer ma boutique', icon: Icons.add, busy: false, onPressed: () => _open(const ShopFormScreen())),
      ],
    );
  }

  Widget _dashboard(Shop shop) {
    final p = Palette.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Heading(shop.name, size: 20)),
                  const SizedBox(width: 8),
                  StatusBadge(shop.statusLabel, action: shop.status != 'approved'),
                ],
              ),
              if (shop.status == 'pending') ...[
                const SizedBox(height: 8),
                const Muted('Votre boutique sera visible dès sa validation. Ajoutez déjà vos articles.', size: 13),
              ],
              if (shop.rejectionReason != null) ...[
                const SizedBox(height: 8),
                Text(shop.rejectionReason!, style: TextStyle(fontSize: 13, color: p.warn)),
                const SizedBox(height: 4),
                const Muted('Corrigez votre boutique pour la renvoyer en validation.', size: 13),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.edit_outlined, size: 20),
          label: const Text('Modifier ma boutique'),
          onPressed: () => _open(ShopFormScreen(shop: shop)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.receipt_long_outlined, size: 20),
          label: const Text('Commandes reçues'),
          onPressed: () => _open(const SellerOrdersScreen()),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.payments_outlined, size: 20),
          label: const Text('Mes gains'),
          onPressed: () => _open(const PayoutsScreen()),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Label('Mes articles (${_products.length})'),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Ajouter'),
              onPressed: () => _open(const ProductFormScreen()),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_products.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Muted('Ajoutez votre premier article pour commencer à vendre.', align: TextAlign.center),
          ),
        for (final product in _products)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              onTap: () => _open(ProductFormScreen(product: product)),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AuthImage(product.imagePath, width: 60, height: 60),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Muted(money(product.price), size: 13),
                        Muted(
                          [
                            product.stock == null ? 'Stock illimité' : 'Stock : ${product.stock}',
                            if (!product.isActive) 'Retiré de la vente',
                          ].join(' · '),
                          size: 12,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
