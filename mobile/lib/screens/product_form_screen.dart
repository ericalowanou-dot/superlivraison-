import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../state/session.dart';
import '../widgets.dart';
import 'photo_field.dart';

/// Ajout ou modification d'un article par le vendeur.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.product});

  final Product? product;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  late final _name = TextEditingController(text: widget.product?.name);
  late final _description = TextEditingController(text: widget.product?.description);
  late final _price = TextEditingController(text: widget.product?.price.toString());
  late final _stock = TextEditingController(text: widget.product?.stock?.toString());

  late bool _active = widget.product?.isActive ?? true;
  XFile? _image;
  bool _sending = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _stock.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final product = widget.product;
    final name = _name.text.trim();
    final price = int.tryParse(_price.text.trim());
    final stock = _stock.text.trim();

    if (product == null && _image == null) return showMessage(context, 'Ajoutez une photo de l\'article.');
    if (name.length < 2) return showMessage(context, 'Donnez un nom à l\'article.');
    if (price == null || price < 1) return showMessage(context, 'Indiquez le prix en FCFA.');

    setState(() => _sending = true);
    final navigator = Navigator.of(context);

    try {
      await AppScope.api(context).postForm(
        product == null ? '/my-shop/products' : '/my-shop/products/${product.id}',
        {
          'name': name,
          'price': '$price',
          'is_active': _active ? '1' : '0',
          if (stock.isNotEmpty) 'stock': stock,
          if (_description.text.trim().isNotEmpty) 'description': _description.text.trim(),
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

  Future<void> _delete() async {
    final product = widget.product!;
    final api = AppScope.api(context);
    final navigator = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cet article ?'),
        content: Text(product.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Retour')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await api.delete('/my-shop/products/${product.id}');
      navigator.pop();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;

    return Scaffold(
      appBar: AppBar(
        title: Text(product == null ? 'Nouvel article' : 'Modifier l\'article'),
        actions: [
          if (product != null) IconButton(tooltip: 'Supprimer', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          children: [
            PhotoField(label: 'Photo de l\'article', existingPath: product?.imagePath, onPicked: (file) => _image = file),
            const SizedBox(height: 16),
            const Label('Nom'),
            const SizedBox(height: 8),
            TextField(controller: _name, maxLength: 120, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(counterText: '')),
            const SizedBox(height: 16),
            const Label('Description (facultatif)'),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              minLines: 2,
              maxLines: 5,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(counterText: ''),
            ),
            const SizedBox(height: 16),
            const Label('Prix en FCFA'),
            const SizedBox(height: 8),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(hintText: 'Exemple : 4000'),
            ),
            const SizedBox(height: 16),
            const Label('Stock (vide si illimité)'),
            const SizedBox(height: 8),
            TextField(
              controller: _stock,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('En vente'),
              value: _active,
              onChanged: (value) => setState(() => _active = value),
            ),
            const SizedBox(height: 8),
            BusyButton(label: 'Enregistrer', busy: _sending, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
