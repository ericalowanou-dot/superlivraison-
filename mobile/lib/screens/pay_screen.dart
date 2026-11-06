import 'dart:async';

import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets.dart';

class PayScreen extends StatefulWidget {
  const PayScreen({super.key, required this.order});

  final Order order;

  @override
  State<PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends State<PayScreen> {
  static const _methods = [
    ('mixx', 'Mixx by Yas'),
    ('flooz', 'Flooz'),
    ('cash', 'Payer à la livraison'),
  ];

  late String _method = 'mixx';
  late final _phone = TextEditingController(text: AppScope.session(context).user?.phone ?? '');
  late bool _accepted = !widget.order.awaitsPrice;
  bool _busy = false;
  bool _waiting = false;
  String? _result;

  /// Une commande déjà acceptée en paiement mobile ne peut plus passer à la livraison.
  List<(String, String)> get _available =>
      widget.order.awaitsPrice ? _methods : _methods.where((m) => m.$1 != 'cash').toList();

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final api = AppScope.api(context);
    final order = widget.order;
    setState(() => _busy = true);

    try {
      if (!_accepted) {
        await api.post('/orders/${order.id}/accept-price', {
          'payment_mode': _method == 'cash' ? 'cash' : 'mobile_money',
          'price': order.price,
        });
        _accepted = true;
      }

      if (_method == 'cash') {
        if (mounted) setState(() => _result = 'cash');
        return;
      }

      final data = await api.post('/orders/${order.id}/payments', {'method': _method, 'phone': _phone.text.trim()});
      if (!mounted) return;

      setState(() => _waiting = true);
      await _watch(Payment.fromJson(data as Map<String, dynamic>));
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _waiting = false;
        });
      }
    }
  }

  /// Le résultat arrive par l'agrégateur : on l'attend sans jamais le supposer.
  Future<void> _watch(Payment payment) async {
    final api = AppScope.api(context);

    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;

      final fresh = Payment.fromJson(await api.get('/payments/${payment.id}') as Map<String, dynamic>);
      if (!fresh.isPending) {
        if (!mounted) return;
        if (fresh.status == 'succeeded') {
          setState(() => _result = 'paid');
        } else {
          showMessage(context, fresh.failureReason ?? 'Le paiement n\'a pas abouti.');
        }
        return;
      }
    }

    if (mounted) showMessage(context, 'Paiement toujours en attente. Consultez l\'onglet Paiements.');
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final order = widget.order;

    return Scaffold(
      appBar: AppBar(title: const Text('Paiement')),
      body: SafeArea(
        child: _result != null
            ? _done()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                children: [
                  AppCard(
                    color: p.soft,
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Label(order.reference),
                          Heading(money(order.price!), size: 28),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Label('Moyen de paiement'),
                  const SizedBox(height: 10),
                  for (final (id, label) in _available)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        color: id == _method ? p.soft : null,
                        onTap: _busy ? null : () => setState(() => _method = id),
                        child: Row(
                          children: [
                            Icon(id == _method ? Icons.radio_button_checked : Icons.radio_button_off, size: 20),
                            const SizedBox(width: 10),
                            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  if (_method != 'cash') ...[
                    const SizedBox(height: 10),
                    const Label('Numéro à débiter'),
                    const SizedBox(height: 8),
                    TextField(controller: _phone, keyboardType: TextInputType.phone, enabled: !_busy),
                  ],
                  if (_waiting) ...[
                    const SizedBox(height: 16),
                    const Muted('Validez le paiement sur votre téléphone.', align: TextAlign.center),
                  ],
                  const SizedBox(height: 20),
                  BusyButton(label: 'Confirmer', busy: _busy, onPressed: _confirm),
                ],
              ),
      ),
    );
  }

  Widget _done() {
    final isCash = _result == 'cash';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircleAvatar(
                  radius: 38,
                  backgroundColor: Palette.sky,
                  child: Icon(Icons.check, size: 38, color: Palette.onSky),
                ),
                const SizedBox(height: 12),
                Heading(isCash ? 'Commande confirmée' : 'Paiement réussi', size: 22),
                const SizedBox(height: 8),
                Muted(
                  isCash
                      ? 'Vous paierez ${money(widget.order.price!)} à la livraison.'
                      : 'Votre commande ${widget.order.reference} va être préparée.',
                  align: TextAlign.center,
                ),
              ],
            ),
          ),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Suivre ma commande')),
        ],
      ),
    );
  }
}
