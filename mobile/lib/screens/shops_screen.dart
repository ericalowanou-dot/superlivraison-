import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets.dart';

/// Annuaire des boutiques de la ville.
class ShopsScreen extends StatefulWidget {
  const ShopsScreen({super.key});

  @override
  State<ShopsScreen> createState() => _ShopsScreenState();
}

class _ShopsScreenState extends State<ShopsScreen> {
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: () => _fetch(1),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        children: [
          TextField(
            onChanged: _onSearch,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(hintText: 'Rechercher une boutique', prefixIcon: Icon(Icons.search)),
          ),
          const SizedBox(height: 16),
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
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopScreen(shop: shop))),
                child: Row(
                  children: [
                    _Thumbnail(shop: shop),
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

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.shop});

  final Shop shop;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: shop.hasImage
          ? AuthImage(shop.imagePath, width: 60, height: 60)
          : ColoredBox(
              color: Palette.of(context).soft,
              child: const SizedBox.square(dimension: 60, child: Icon(Icons.storefront_outlined)),
            ),
    );
  }
}

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key, required this.shop});

  final Shop shop;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(shop.name)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          children: [
            if (shop.hasImage) ...[
              ClipRRect(borderRadius: BorderRadius.circular(12), child: AuthImage(shop.imagePath, fit: BoxFit.fitWidth)),
              const SizedBox(height: 16),
            ],
            Heading(shop.name, size: 22),
            if (shop.category != null) ...[
              const SizedBox(height: 6),
              Align(alignment: Alignment.centerLeft, child: StatusBadge(shop.category!)),
            ],
            if (shop.description != null) ...[
              const SizedBox(height: 12),
              Text(shop.description!, style: const TextStyle(fontSize: 15)),
            ],
            if (shop.landmark != null) ...[
              const SizedBox(height: 12),
              Muted(shop.landmark!),
            ],
            const SizedBox(height: 20),
            if (shop.phone != null)
              BusyButton(label: 'Appeler', icon: Icons.call_outlined, busy: false, onPressed: () => callPhone(context, shop.phone!)),
            if (shop.lat != null && shop.lng != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(onPressed: () => openMap(context, shop.lat!, shop.lng!), child: const Text('Voir sur la carte')),
            ],
          ],
        ),
      ),
    );
  }
}
