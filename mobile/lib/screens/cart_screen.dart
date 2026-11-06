import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../format.dart';
import '../state/cart.dart';
import '../state/session.dart';
import '../widgets.dart';
import 'map_screen.dart';
import 'order_screen.dart';
import 'shop_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key, required this.cart});

  final Cart cart;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _landmark = TextEditingController();
  // Garde le même identifiant si l'envoi est relancé : pas de double achat.
  final _clientUuid = const Uuid().v4();

  LatLng? _point;
  bool _sending = false;

  @override
  void dispose() {
    _landmark.dispose();
    super.dispose();
  }

  Future<void> _pickPoint() async {
    final point = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => MapScreen(initial: _point)),
    );
    if (point != null) setState(() => _point = point);
  }

  Future<void> _order() async {
    final cart = widget.cart;
    final landmark = _landmark.text.trim();

    if (_point == null) return showMessage(context, 'Placez le point de livraison sur la carte.');
    if (landmark.isEmpty) return showMessage(context, 'Indiquez un repère pour le livreur.');

    setState(() => _sending = true);
    final navigator = Navigator.of(context);

    try {
      final data = await AppScope.api(context).post('/shops/${cart.shop!.id}/orders', {
        'client_uuid': _clientUuid,
        'items': [
          for (final line in cart.lines) {'product_id': line.product.id, 'quantity': line.quantity},
        ],
        'delivery_lat': _point!.latitude,
        'delivery_lng': _point!.longitude,
        'delivery_landmark': landmark,
      }) as Map<String, dynamic>;

      cart.clear();
      if (!mounted) return;
      showMessage(context, 'Commande envoyée. Un opérateur fixe les frais de livraison.');
      navigator.pop();
      navigator.pushReplacement(MaterialPageRoute(builder: (_) => OrderScreen(orderId: data['id'] as int)));
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mon panier')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.cart,
          builder: (context, _) {
            final cart = widget.cart;

            if (cart.isEmpty) {
              return const Center(child: Muted('Votre panier est vide.'));
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              children: [
                Heading(cart.shop!.name, size: 20),
                const SizedBox(height: 12),
                for (final line in cart.lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppCard(
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AuthImage(line.product.imagePath, width: 60, height: 60),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(line.product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                Muted(money(line.subtotal), size: 13),
                                const SizedBox(height: 4),
                                QuantityStepper(
                                  quantity: line.quantity,
                                  onRemove: () => cart.remove(line.product),
                                  onAdd: cart.canAdd(line.product) ? () => cart.add(cart.shop!, line.product) : null,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Label('Total des articles'),
                    Text(money(cart.total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 4),
                const Muted('Les frais de livraison vous sont proposés avant le paiement.', size: 13),
                const SizedBox(height: 20),
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
                            const Text('Point de livraison', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            Muted(_point == null ? 'Placer sur la carte' : 'Position enregistrée', size: 13),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Label('Repère pour le livreur'),
                const SizedBox(height: 8),
                TextField(
                  controller: _landmark,
                  maxLength: 255,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Exemple : face à la pharmacie du marché', counterText: ''),
                ),
                const SizedBox(height: 16),
                BusyButton(label: 'Commander', icon: Icons.check, busy: _sending, onPressed: _order),
              ],
            );
          },
        ),
      ),
    );
  }
}
