import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../state/session.dart';
import '../widgets.dart';

/// Commandes reçues par le vendeur : les articles à préparer.
class SellerOrdersScreen extends StatefulWidget {
  const SellerOrdersScreen({super.key});

  @override
  State<SellerOrdersScreen> createState() => _SellerOrdersScreenState();
}

class _SellerOrdersScreenState extends State<SellerOrdersScreen> {
  List<SellerOrder> _orders = [];
  bool _loading = true;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _orders.isEmpty && _error == null) _fetch();
  }

  Future<void> _fetch() async {
    try {
      final data = await AppScope.api(context).get('/my-shop/orders') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _orders = (data['data'] as List).map((o) => SellerOrder.fromJson(o as Map<String, dynamic>)).toList();
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
    return Scaffold(
      appBar: AppBar(title: const Text('Commandes reçues')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _orders.isEmpty
              ? ErrorRetry(error: _error!, onRetry: _fetch)
              : RefreshIndicator(
                  onRefresh: _fetch,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    children: [
                      if (_orders.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Muted('Aucune commande pour le moment.', align: TextAlign.center),
                        ),
                      for (final order in _orders)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(order.reference, style: const TextStyle(fontWeight: FontWeight.w700)),
                                    StatusBadge(order.statusLabel),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                for (final item in order.items) Text('${item.quantity} × ${item.name}'),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Muted(shortDate(order.createdAt), size: 12),
                                    Text(money(order.goodsTotal), style: const TextStyle(fontWeight: FontWeight.w800)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

/// Ce que la plateforme a reversé ou doit reverser au vendeur.
class PayoutsScreen extends StatefulWidget {
  const PayoutsScreen({super.key});

  @override
  State<PayoutsScreen> createState() => _PayoutsScreenState();
}

class _PayoutsScreenState extends State<PayoutsScreen> {
  List<Payout> _payouts = [];
  int _toReceive = 0;
  bool _loading = true;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _payouts.isEmpty && _error == null) _fetch();
  }

  Future<void> _fetch() async {
    try {
      final data = await AppScope.api(context).get('/my-shop/payouts') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _payouts = (data['data'] as List).map((p) => Payout.fromJson(p as Map<String, dynamic>)).toList();
        _toReceive = data['to_receive'] as int;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Mes gains')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _payouts.isEmpty
              ? ErrorRetry(error: _error!, onRetry: _fetch)
              : RefreshIndicator(
                  onRefresh: _fetch,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    children: [
                      AppCard(
                        child: SizedBox(
                          width: double.infinity,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Label('À recevoir'),
                              const SizedBox(height: 2),
                              Heading(money(_toReceive), size: 28),
                              const SizedBox(height: 4),
                              const Muted('Reversé après chaque livraison, commission déduite.', size: 13),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_payouts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Muted('Vos gains apparaîtront après votre première livraison.', align: TextAlign.center),
                        ),
                      for (final payout in _payouts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(payout.orderReference ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                                    Text(money(payout.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Flexible(child: Muted('Commission : ${money(payout.commission)}', size: 13)),
                                    const SizedBox(width: 8),
                                    Muted(payout.statusLabel, size: 13),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
