import 'package:flutter/material.dart';

import '../state/session.dart';
import '../widgets.dart';
import 'setup_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _themes = {ThemeMode.system: 'Téléphone', ThemeMode.light: 'Clair', ThemeMode.dark: 'Sombre'};

  Future<void> _delete(BuildContext context) async {
    final session = AppScope.session(context);
    final navigator = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer mon compte ?'),
        content: const Text('Vos données personnelles seront effacées. Cette action est définitive.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Retour')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await session.deleteAccount();
      navigator.popUntil((route) => route.isFirst);
    } catch (e) {
      if (context.mounted) showMessage(context, errorText(e));
    }
  }

  Future<void> _logout(BuildContext context) async {
    final navigator = Navigator.of(context);
    await AppScope.session(context).logout();
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.session(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: session,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Label('Thème'),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: [
                    for (final entry in _themes.entries) ButtonSegment(value: entry.key, label: Text(entry.value)),
                  ],
                  selected: {session.themeMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => session.setTheme(s.first),
                ),
                const SizedBox(height: 16),
                AppCard(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SetupScreen(fromSettings: true)),
                  ),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Langue, pays et ville', style: TextStyle(fontWeight: FontWeight.w600))),
                      Muted(session.user?.cityName ?? ''),
                    ],
                  ),
                ),
                const Spacer(),
                OutlinedButton(onPressed: () => _logout(context), child: const Text('Se déconnecter')),
                const SizedBox(height: 10),
                OutlinedButton(onPressed: () => _delete(context), child: const Text('Supprimer mon compte')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
