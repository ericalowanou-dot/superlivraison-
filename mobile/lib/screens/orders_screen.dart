import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../state/session.dart';
import '../widgets.dart';
import 'new_order_screen.dart';
import 'order_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final List<Order> _orders = [];
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _orders.isEmpty && _error == null) _refresh();
  }

  Future<void> _refresh() async {
    final outbox = AppScope.outbox(context);
    await outbox.flush();
    await _fetch(1);
  }

  Future<void> _fetch(int page) async {
    try {
      final data = await AppScope.api(context).get('/orders?page=$page') as Map<String, dynamic>;
      final items = (data['data'] as List).map((o) => Order.fromJson(o as Map<String, dynamic>));
      final meta = data['meta'] as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        if (page == 1) _orders.clear();
        _orders.addAll(items);
        _page = page;
        _hasMore = (meta['current_page'] as int) < (meta['last_page'] as int);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    await _fetch(1);
  }

  @override
  Widget build(BuildContext context) {
    final outbox = AppScope.outbox(context);

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _orders.isEmpty) return ErrorRetry(error: _error!, onRetry: _refresh);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListenableBuilder(
        listenable: outbox,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          children: [
            BusyButton(
              label: 'Nouvelle commande',
              icon: Icons.add,
              busy: false,
              onPressed: () => _open(const NewOrderScreen()),
            ),
            if (outbox.items.isNotEmpty) ...[
              const SizedBox(height: 12),
              AppCard(
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Muted(outbox.items.length == 1
                          ? '1 demande sera envoyée au retour du réseau.'
                          : '${outbox.items.length} demandes seront envoyées au retour du réseau.'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Label('Mes commandes'),
            const SizedBox(height: 12),
            if (_orders.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Muted('Vous n\'avez pas encore de commande.', align: TextAlign.center),
              ),
            for (final order in _orders)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OrderCard(order: order, onTap: () => _open(OrderScreen(orderId: order.id))),
              ),
            if (_hasMore)
              OutlinedButton(
                onPressed: _loadingMore
                    ? null
                    : () {
                        setState(() => _loadingMore = true);
                        _fetch(_page + 1);
                      },
                child: const Text('Voir plus'),
              ),
          ],
        ),
      ),
    );
  }
}

class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order, required this.onTap});

  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(order.reference, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              StatusBadge(order.statusLabel, action: order.awaitsPrice || order.awaitsMobilePayment),
            ],
          ),
          const SizedBox(height: 6),
          Text(order.requestText, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 6),
          Muted(shortDate(order.createdAt), size: 12),
        ],
      ),
    );
  }
}
