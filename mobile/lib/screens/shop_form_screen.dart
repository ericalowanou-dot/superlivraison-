import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../models.dart';
import '../state/session.dart';
import '../widgets.dart';
import 'map_screen.dart';
import 'photo_field.dart';

/// Création ou modification de sa boutique.
class ShopFormScreen extends StatefulWidget {
  const ShopFormScreen({super.key, this.shop});

  final Shop? shop;

  @override
  State<ShopFormScreen> createState() => _ShopFormScreenState();
}

class _ShopFormScreenState extends State<ShopFormScreen> {
  late final _name = TextEditingController(text: widget.shop?.name);
  late final _category = TextEditingController(text: widget.shop?.category);
  late final _description = TextEditingController(text: widget.shop?.description);
  late final _phone = TextEditingController(text: widget.shop?.phone ?? '+228 ');
  late final _landmark = TextEditingController(text: widget.shop?.landmark);

  late LatLng? _point = widget.shop?.lat == null ? null : LatLng(widget.shop!.lat!, widget.shop!.lng!);
  XFile? _image;
  bool _sending = false;

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _description.dispose();
    _phone.dispose();
    _landmark.dispose();
    super.dispose();
  }

  Future<void> _pickPoint() async {
    final point = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => MapScreen(initial: _point, title: 'Position de la boutique')),
    );
    if (point != null) setState(() => _point = point);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final landmark = _landmark.text.trim();

    if (name.length < 2) return showMessage(context, 'Donnez un nom à votre boutique.');
    if (phone.length < 8) return showMessage(context, 'Indiquez le numéro de la boutique.');
    if (landmark.isEmpty) return showMessage(context, 'Indiquez où le livreur retire les commandes.');

    setState(() => _sending = true);
    final navigator = Navigator.of(context);

    try {
      await AppScope.api(context).postForm(
        '/my-shop',
        {
          'name': name,
          'phone': phone,
          'landmark': landmark,
          if (_category.text.trim().isNotEmpty) 'category': _category.text.trim(),
          if (_description.text.trim().isNotEmpty) 'description': _description.text.trim(),
          if (_point != null) 'lat': '${_point!.latitude}',
          if (_point != null) 'lng': '${_point!.longitude}',
        },
        fileField: 'image',
        file: _image,
      );
      navigator.pop();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = widget.shop;

    return Scaffold(
      appBar: AppBar(title: Text(shop == null ? 'Créer ma boutique' : 'Modifier ma boutique')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          children: [
            PhotoField(
              label: 'Photo de la boutique',
              existingPath: shop != null && shop.hasImage ? shop.imagePath : null,
              onPicked: (file) => _image = file,
            ),
            const SizedBox(height: 16),
            const Label('Nom de la boutique'),
            const SizedBox(height: 8),
            TextField(controller: _name, maxLength: 120, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(counterText: '')),
            const SizedBox(height: 16),
            const Label('Activité (facultatif)'),
            const SizedBox(height: 8),
            TextField(
              controller: _category,
              maxLength: 100,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Exemple : épicerie, vêtements', counterText: ''),
            ),
            const SizedBox(height: 16),
            const Label('Téléphone'),
            const SizedBox(height: 8),
            TextField(controller: _phone, keyboardType: TextInputType.phone, maxLength: 30, decoration: const InputDecoration(counterText: '')),
            const SizedBox(height: 16),
            const Label('Lieu de retrait pour le livreur'),
            const SizedBox(height: 8),
            TextField(
              controller: _landmark,
              maxLength: 255,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Exemple : marché de Bè, allée 3', counterText: ''),
            ),
            const SizedBox(height: 12),
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
                        const Text('Position de la boutique', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        Muted(_point == null ? 'Placer sur la carte (facultatif)' : 'Position enregistrée', size: 13),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Label('Description (facultatif)'),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(counterText: ''),
            ),
            const SizedBox(height: 16),
            BusyButton(label: shop == null ? 'Envoyer pour validation' : 'Enregistrer', busy: _sending, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
