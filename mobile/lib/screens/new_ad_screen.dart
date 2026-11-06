import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../state/session.dart';
import '../widgets.dart';

class NewAdScreen extends StatefulWidget {
  const NewAdScreen({super.key});

  @override
  State<NewAdScreen> createState() => _NewAdScreenState();
}

class _NewAdScreenState extends State<NewAdScreen> {
  static const _categories = {'advert': 'Publicité', 'concert': 'Concert', 'other': 'Autre'};

  final _title = TextEditingController();
  final _description = TextEditingController();

  String _category = 'advert';
  XFile? _image;
  Uint8List? _preview;
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
      if (image == null) return;

      final bytes = await image.readAsBytes();
      if (mounted) {
        setState(() {
          _image = image;
          _preview = bytes;
        });
      }
    } catch (_) {
      if (mounted) showMessage(context, 'Image illisible. Choisissez-en une autre.');
    }
  }

  Future<void> _send() async {
    final title = _title.text.trim();
    final description = _description.text.trim();

    if (_image == null) return showMessage(context, 'Choisissez une affiche.');
    if (title.length < 3) return showMessage(context, 'Donnez un titre à votre affiche.');

    setState(() => _sending = true);
    final navigator = Navigator.of(context);

    try {
      await AppScope.api(context).upload('/ads', 'image', _image!.path, _image!.name, {
        'category': _category,
        'title': title,
        if (description.isNotEmpty) 'description': description,
      });
      navigator.pop(true);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Publier une affiche')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          children: [
            const Muted('Votre affiche sera visible dans votre ville après validation par notre équipe.'),
            const SizedBox(height: 16),
            AppCard(
              onTap: _pick,
              child: _preview == null
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Column(
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 36),
                          SizedBox(height: 8),
                          Text('Choisir une affiche', style: TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    )
                  : ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(_preview!, fit: BoxFit.fitWidth)),
            ),
            const SizedBox(height: 16),
            const Label('Type'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in _categories.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _category == entry.key,
                    onSelected: (_) => setState(() => _category = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Label('Titre'),
            const SizedBox(height: 8),
            TextField(
              controller: _title,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Exemple : Concert au stade de Kégué', counterText: ''),
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
              decoration: const InputDecoration(hintText: 'Date, lieu, prix, contact...', counterText: ''),
            ),
            const SizedBox(height: 16),
            BusyButton(label: 'Envoyer pour validation', busy: _sending, onPressed: _send),
          ],
        ),
      ),
    );
  }
}
