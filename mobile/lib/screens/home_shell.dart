import 'package:flutter/material.dart';

import 'ads_screen.dart';
import 'courier_request_screen.dart';
import 'orders_screen.dart';
import 'settings_screen.dart';
import 'shops_screen.dart';

/// Les quatre pages du restaurant. Les paiements s'ouvrent depuis Commandes.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _titles = ['Solliciter un livreur', 'Commandes', 'Publicités', 'Boutiques'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Image.asset('assets/logo.png', width: 36, height: 36, excludeFromSemantics: true),
            const SizedBox(width: 10),
            Flexible(child: Text(_titles[_tab], overflow: TextOverflow.ellipsis)),
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
      body: IndexedStack(
        index: _tab,
        children: const [CourierRequestScreen(), OrdersScreen(), AdsScreen(), ShopsScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.delivery_dining_outlined), label: 'Livreur'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Commandes'),
          NavigationDestination(icon: Icon(Icons.campaign_outlined), label: 'Publicités'),
          NavigationDestination(icon: Icon(Icons.storefront_outlined), label: 'Boutiques'),
        ],
      ),
    );
  }
}
