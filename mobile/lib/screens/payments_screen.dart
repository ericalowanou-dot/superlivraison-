import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../format.dart';
import '../models.dart';
import '../state/session.dart';
import '../widgets.dart';
import 'pay_screen.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  List<Order> _due = [];
  final List<Payment> _history = [];
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _history.isEmpty && _error == null) _refresh();
  }

  Future<void> _refresh() async {
    final api = AppScope.api(context);

    try {
      final due = await api.get('/orders?to_pay=1') as Map<String, dynamic>;
      final history = await api.get('/payments?page=1') as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _due = (due['data'] as List).map((o) => Order.fromJson(o as Map<String, dynamic>)).toList();
        _history
          ..clear()
          ..addAll(_payments(history));
        _page = 1;
        _hasMore = _more(history);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _nextPage() async {
    try {
      final data = await AppScope.api(context).get('/payments?page=${_page + 1}') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _history.addAll(_payments(data));
        _page++;
        _hasMore = _more(data);
      });
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    }
  }

  Iterable<Payment> _payments(Map<String, dynamic> data) =>
      (data['data'] as List).map((p) => Payment.fromJson(p as Map<String, dynamic>));

  bool _more(Map<String, dynamic> data) {
    final meta = data['meta'] as Map<String, dynamic>;
    return (meta['current_page'] as int) < (meta['last_page'] as int);
  }

  Future<void> _receipt(Payment payment) async {
    if (kIsWeb) return showMessage(context, 'Le reçu se télécharge depuis l\'application mobile.');

    try {
      final bytes = await AppScope.api(context).download('/payments/${payment.id}/receipt');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/recu-${payment.orderReference ?? payment.id}.pdf');
      await file.writeAsBytes(bytes);
      await OpenFilex.open(file.path);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    }
  }

  Future<void> _pay(Order order) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PayScreen(order: order)));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _history.isEmpty && _due.isEmpty) return ErrorRetry(error: _error!, onRetry: _refresh);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        children: [
          const Label('À payer'),
          const SizedBox(height: 10),
          if (_due.isEmpty) const Muted('Aucun paiement en attente.'),
          for (final order in _due)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(order.reference, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        Text(money(order.price!), style: const TextStyle(fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Muted(order.requestText),
                    const SizedBox(height: 10),
                    FilledButton(onPressed: () => _pay(order), child: const Text('Payer')),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          const Label('Historique'),
          const SizedBox(height: 10),
          if (_history.isEmpty) const Muted('Aucun paiement pour le moment.'),
          for (final payment in _history)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                onTap: payment.hasReceipt ? () => _receipt(payment) : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(payment.orderReference ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        Text(money(payment.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(child: Muted('${payment.methodLabel} · ${shortDate(payment.createdAt)}', size: 13)),
                        const SizedBox(width: 8),
                        Muted(payment.statusLabel, size: 13),
                      ],
                    ),
                    if (payment.hasReceipt) ...[
                      const SizedBox(height: 4),
                      const Muted('Touchez pour ouvrir le reçu', size: 12),
                    ],
                  ],
                ),
              ),
            ),
          if (_hasMore) OutlinedButton(onPressed: _nextPage, child: const Text('Voir plus')),
        ],
      ),
    );
  }
}
