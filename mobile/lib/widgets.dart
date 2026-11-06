import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api/api_client.dart';
import 'state/session.dart';
import 'theme.dart';

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.color});

  final Widget child;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final radius = BorderRadius.circular(16);

    return Material(
      color: color ?? p.surface,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: p.line)),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(14), child: child),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.action = false});

  final String label;
  final bool action;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: action ? p.warnBg : p.soft, borderRadius: BorderRadius.circular(12)),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: action ? p.warn : p.ink),
      ),
    );
  }
}

class Label extends StatelessWidget {
  const Label(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700));
}

class Muted extends StatelessWidget {
  const Muted(this.text, {super.key, this.align, this.size = 14});

  final String text;
  final TextAlign? align;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Text(text, textAlign: align, style: TextStyle(color: Palette.of(context).muted, fontSize: size));
}

class Heading extends StatelessWidget {
  const Heading(this.text, {super.key, this.size = 26});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: size, height: 1.15, fontWeight: FontWeight.w800));
}

/// Bouton principal qui affiche un indicateur pendant l'action.
class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.label, required this.busy, required this.onPressed, this.icon});

  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                Flexible(child: Text(label)),
              ],
            ),
    );
  }
}

/// Message d'erreur avec relance, pour les listes et les détails.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Muted(errorText(error), align: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}

/// Image de l'API : le serveur demande le jeton de connexion.
class AuthImage extends StatelessWidget {
  const AuthImage(this.path, {super.key, this.width, this.height, this.fit = BoxFit.cover});

  final String path;
  final double? width, height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final api = AppScope.api(context);

    return Image.network(
      api.url(path),
      headers: api.authHeaders,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stack) => SizedBox(
        width: width,
        height: height ?? 120,
        child: const Center(child: Icon(Icons.broken_image_outlined)),
      ),
    );
  }
}

Future<void> _openExternal(BuildContext context, Uri uri, String failure) async {
  final messenger = ScaffoldMessenger.of(context);

  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    // Le message ci-dessous couvre ce cas.
  }
  messenger.showSnackBar(SnackBar(content: Text(failure)));
}

Future<void> callPhone(BuildContext context, String phone) =>
    _openExternal(context, Uri(scheme: 'tel', path: phone), 'Appel impossible depuis ce téléphone.');

Future<void> openMap(BuildContext context, double lat, double lng) => _openExternal(
      context,
      Uri.parse('https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=18/$lat/$lng'),
      'Carte impossible à ouvrir.',
    );

String errorText(Object error) => error is ApiException || error is NetworkException
    ? error.toString()
    : 'Une erreur est survenue. Réessayez.';

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
