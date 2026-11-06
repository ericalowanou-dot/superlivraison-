import 'package:flutter/material.dart';

import '../models.dart';
import '../state/session.dart';
import '../widgets.dart';

/// Espace du livreur : ses livraisons en cours, sans les onglets du restaurant.
class CourierScreen extends StatefulWidget {
  const CourierScreen({super.key});

  @override
  State<CourierScreen> createState() => _CourierScreenState();
}

class _CourierScreenState extends State<CourierScreen> {
  List<Order> _orders = [];
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _orders.isEmpty && _error == null) _fetch();
  }

  Future<void> _fetch() async {
    try {
      final data = await AppScope.api(context).get('/courier/deliveries') as List;
      if (mounted) {
        setState(() {
          _orders = data.map((o) => Order.fromJson(o as Map<String, dynamic>)).toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(String path) async {
    final api = AppScope.api(context);
    setState(() => _busy = true);

    try {
      await api.post(path);
      await _fetch();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes livraisons'),
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: () => AppScope.session(context).logout(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _orders.isEmpty
              ? ErrorRetry(error: _error!, onRetry: _fetch)
              : RefreshIndicator(
                  onRefresh: _fetch,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_orders.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Muted('Aucune livraison pour le moment.', align: TextAlign.center),
                        ),
                      for (final order in _orders)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AppCard(child: _card(order)),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _card(Order order) {
    final collect = order.paymentMode == 'cash' && order.price != null;

    return Column(
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
        Text(order.requestText),
        const SizedBox(height: 6),
        Muted('Repère : ${order.landmark}', size: 13),
        if (collect) Muted('À encaisser : ${order.price} FCFA', size: 13),
        if (order.recipientPhone != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.call_outlined, size: 20),
            label: Text('Appeler ${order.recipientPhone}'),
            onPressed: () => callPhone(context, order.recipientPhone!),
          ),
        ],
        if (order.lat != null && order.lng != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.place_outlined, size: 20),
            label: const Text('Voir sur la carte'),
            onPressed: () => openMap(context, order.lat!, order.lng!),
          ),
        ],
        const SizedBox(height: 10),
        if (order.status == 'preparing')
          BusyButton(label: 'Démarrer la livraison', busy: _busy, onPressed: () => _act('/courier/deliveries/${order.id}/start')),
        if (order.status == 'delivering')
          BusyButton(label: collect ? 'Livrée et encaissée' : 'Marquer livrée', busy: _busy, onPressed: () => _act('/courier/deliveries/${order.id}/delivered')),
      ],
    );
  }
}
