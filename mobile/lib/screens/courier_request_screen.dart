import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../state/session.dart';
import '../widgets.dart';
import 'map_screen.dart';
import 'order_screen.dart';
import 'orders_screen.dart';

/// Solliciter un livreur : le numéro et la position du destinataire suffisent.
class CourierRequestScreen extends StatefulWidget {
  const CourierRequestScreen({super.key});

  @override
  State<CourierRequestScreen> createState() => _CourierRequestScreenState();
}

class _CourierRequestScreenState extends State<CourierRequestScreen> {
  final _phone = TextEditingController(text: '+228 ');
  final _landmark = TextEditingController();
  final _details = TextEditingController();

  // Garde le même identifiant si l'envoi est relancé : pas de double course.
  String _clientUuid = const Uuid().v4();
  LatLng? _point;
  List<Order> _requests = [];
  bool _started = false;
  bool _sending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _fetch();
  }

  @override
  void dispose() {
    _phone.dispose();
    _landmark.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final data = await AppScope.api(context).get('/orders?kind=courier') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _requests = (data['data'] as List).map((o) => Order.fromJson(o as Map<String, dynamic>)).toList();
      });
    } catch (_) {
      // La liste reste vide : le formulaire doit rester utilisable sans elle.
    }
  }

  Future<void> _pickPoint() async {
    final point = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => MapScreen(initial: _point, title: 'Position du destinataire')),
    );
    if (point != null) setState(() => _point = point);
  }

  Future<void> _send() async {
    final phone = _phone.text.trim();
    final landmark = _landmark.text.trim();
    final details = _details.text.trim();

    if (phone.length < 8) return showMessage(context, 'Indiquez le numéro du destinataire.');
    if (_point == null) return showMessage(context, 'Placez le destinataire sur la carte.');

    setState(() => _sending = true);

    try {
      await AppScope.api(context).post('/courier-requests', {
        'client_uuid': _clientUuid,
        'recipient_phone': phone,
        'delivery_lat': _point!.latitude,
        'delivery_lng': _point!.longitude,
        if (landmark.isNotEmpty) 'delivery_landmark': landmark,
        if (details.isNotEmpty) 'details': details,
      });

      if (!mounted) return;
      showMessage(context, 'Demande envoyée. Un opérateur prépare le prix.');
      setState(() {
        _clientUuid = const Uuid().v4();
        _point = null;
        _phone.text = '+228 ';
        _landmark.clear();
        _details.clear();
      });
      await _fetch();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _open(Order order) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderScreen(orderId: order.id)));
    await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        children: [
          const Muted('Un livreur vient chercher votre colis et le remet à votre destinataire.'),
          const SizedBox(height: 16),
          const Label('Téléphone du destinataire'),
          const SizedBox(height: 8),
          TextField(controller: _phone, keyboardType: TextInputType.phone, maxLength: 30, decoration: const InputDecoration(counterText: '')),
          const SizedBox(height: 16),
          AppCard(
            onTap: _pickPoint,
            child: Row(
              children: [
                const Icon(Icons.place_outlined, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Position du destinataire', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      Muted(_point == null ? 'Placer sur la carte' : 'Position enregistrée', size: 13),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Label('Repère (facultatif)'),
          const SizedBox(height: 8),
          TextField(
            controller: _landmark,
            maxLength: 255,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Exemple : face à la pharmacie du marché', counterText: ''),
          ),
          const SizedBox(height: 16),
          const Label('Précisions pour le livreur (facultatif)'),
          const SizedBox(height: 8),
          TextField(
            controller: _details,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Exemple : colis à récupérer au marché de Bè', counterText: ''),
          ),
          const SizedBox(height: 16),
          BusyButton(label: 'Solliciter un livreur', icon: Icons.delivery_dining_outlined, busy: _sending, onPressed: _send),
          if (_requests.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Label('Mes courses'),
            const SizedBox(height: 12),
            for (final order in _requests)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OrderCard(order: order, onTap: () => _open(order)),
              ),
          ],
        ],
      ),
    );
  }
}
