import 'dart:async';

import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'pay_screen.dart';

class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key, required this.orderId});

  final int orderId;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  // Sans notifications en direct pour l'instant, le suivi se met à jour tout seul à l'écran.
  static const _refreshEvery = Duration(seconds: 20);

  static const _steps = [
    ('received', 'Reçue'),
    ('price_pending', 'Prix à valider'),
    ('confirmed', 'Confirmée'),
    ('preparing', 'En préparation'),
    ('delivering', 'En livraison'),
    ('delivered', 'Livrée'),
  ];

  Order? _order;
  Object? _error;
  bool _busy = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
    _timer = Timer.periodic(_refreshEvery, (_) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final data = await AppScope.api(context).get('/orders/${widget.orderId}');
      if (mounted) {
        setState(() {
          _order = Order.fromJson(data as Map<String, dynamic>);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _fetch();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
      await _fetch();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PayScreen(order: _order!)));
    await _fetch();
  }

  Future<void> _refuse() async {
    final api = AppScope.api(context);
    final reason = await _askReason('Refuser ce prix', 'Motif, facultatif', required: false);
    if (reason == null) return;
    await _act(() => api.post('/orders/${widget.orderId}/refuse-price', {if (reason.isNotEmpty) 'reason': reason}));
  }

  Future<void> _cancel() async {
    final api = AppScope.api(context);
    final reason = await _askReason('Annuler la commande', 'Motif', required: true);
    if (reason == null) return;
    await _act(() => api.post('/orders/${widget.orderId}/cancel', {'reason': reason}));
  }

  Future<void> _reorder() async {
    final api = AppScope.api(context);
    final navigator = Navigator.of(context);
    await _act(() async {
      await api.post('/orders/${widget.orderId}/reorder');
      if (mounted) showMessage(context, 'Nouvelle demande envoyée.');
      navigator.pop();
    });
  }

  Future<String?> _askReason(String title, String hint, {required bool required}) {
    final field = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: field, autofocus: true, maxLength: 255, decoration: InputDecoration(hintText: hint, counterText: '')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Retour')),
          TextButton(
            onPressed: () {
              final text = field.text.trim();
              if (required && text.isEmpty) return;
              Navigator.pop(context, text);
            },
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;

    return Scaffold(
      appBar: AppBar(title: Text(order?.reference ?? 'Commande')),
      body: SafeArea(
        child: order == null
            ? (_error != null
                ? ErrorRetry(error: _error!, onRetry: _fetch)
                : const Center(child: CircularProgressIndicator()))
            : RefreshIndicator(onRefresh: _fetch, child: _content(order)),
      ),
    );
  }

  Widget _content(Order order) {
    final p = Palette.of(context);
    const gap = SizedBox(height: 12);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusBadge(order.statusLabel, action: order.awaitsPrice || order.awaitsMobilePayment),
              const SizedBox(height: 8),
              Text(order.requestText, style: const TextStyle(fontSize: 15)),
              const SizedBox(height: 8),
              Muted('Repère : ${order.landmark}', size: 13),
              if (order.recipientPhone != null) Muted('Destinataire : ${order.recipientPhone}', size: 13),
              if (order.hasVoice) const Muted('Vocal joint', size: 13),
            ],
          ),
        ),
        gap,
        if (order.status == 'received') ...[
          const Muted('Un opérateur lit votre demande et prépare le prix.'),
          gap,
        ],
        if (order.awaitsPrice) ...[
          AppCard(
            color: p.soft,
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Label('Prix proposé, livraison comprise'),
                  const SizedBox(height: 2),
                  Heading(money(order.price!), size: 28),
                ],
              ),
            ),
          ),
          gap,
          BusyButton(label: 'Accepter et payer', busy: _busy, onPressed: _pay),
          gap,
          OutlinedButton(onPressed: _busy ? null : _refuse, child: const Text('Refuser ce prix')),
          gap,
        ],
        if (order.awaitsMobilePayment) ...[
          BusyButton(label: 'Payer ${money(order.price!)}', busy: _busy, onPressed: _pay),
          gap,
        ],
        if (order.isCancelled) ...[
          AppCard(color: p.warnBg, child: SizedBox(width: double.infinity, child: Text(order.cancelReason ?? 'Commande annulée', style: TextStyle(color: p.warn)))),
          gap,
        ],
        if (!order.isCancelled) ...[
          AppCard(child: SizedBox(width: double.infinity, child: _tracking(order))),
          gap,
        ],
        if (order.canCancel) ...[
          OutlinedButton(onPressed: _busy ? null : _cancel, child: const Text('Annuler la commande')),
          gap,
        ],
        if (order.status == 'delivered' || order.isCancelled)
          OutlinedButton(onPressed: _busy ? null : _reorder, child: const Text('Recommander')),
      ],
    );
  }

  Widget _tracking(Order order) {
    final p = Palette.of(context);
    final current = _steps.indexWhere((s) => s.$1 == order.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Label('Suivi'),
        const SizedBox(height: 6),
        for (final (index, step) in _steps.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index <= current ? Palette.sky : p.line,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  step.$2,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: index == current ? FontWeight.w700 : FontWeight.w400,
                    color: index <= current ? p.ink : p.muted,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
