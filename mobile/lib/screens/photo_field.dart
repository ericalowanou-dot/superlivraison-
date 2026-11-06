import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets.dart';

/// Choix d'une photo dans la galerie, avec aperçu.
class PhotoField extends StatefulWidget {
  const PhotoField({super.key, required this.label, required this.onPicked, this.existingPath});

  final String label;
  final ValueChanged<XFile> onPicked;

  /// Photo déjà enregistrée sur le serveur.
  final String? existingPath;

  @override
  State<PhotoField> createState() => _PhotoFieldState();
}

class _PhotoFieldState extends State<PhotoField> {
  Uint8List? _preview;

  Future<void> _pick() async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
      if (image == null) return;

      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() => _preview = bytes);
      widget.onPicked(image);
    } catch (_) {
      if (mounted) showMessage(context, 'Image illisible. Choisissez-en une autre.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;

    if (_preview != null) {
      content = Image.memory(_preview!, height: 180, width: double.infinity, fit: BoxFit.cover);
    } else if (widget.existingPath != null) {
      content = AuthImage(widget.existingPath!, height: 180, width: double.infinity);
    } else {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            const Icon(Icons.add_photo_alternate_outlined, size: 34),
            const SizedBox(height: 8),
            Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    return AppCard(
      onTap: _pick,
      child: Center(child: ClipRRect(borderRadius: BorderRadius.circular(10), child: content)),
    );
  }
}
