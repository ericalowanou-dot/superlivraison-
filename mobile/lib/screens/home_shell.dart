import 'package:flutter/material.dart';

import 'orders_screen.dart';
import 'payments_screen.dart';
import 'settings_screen.dart';

/// Phase 1 : Commandes et Paiements. Le marché arrive en phase 2 et l'onglet 1 reste à définir.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _titles = ['Commandes', 'Paiements'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Image.asset('assets/logo.png', width: 36, height: 36, excludeFromSemantics: true),
            const SizedBox(width: 10),
            Text(_titles[_tab]),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Réglages',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(index: _tab, children: const [OrdersScreen(), PaymentsScreen()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Commandes'),
          NavigationDestination(icon: Icon(Icons.credit_card_outlined), label: 'Paiements'),
        ],
      ),
    );
  }
}
