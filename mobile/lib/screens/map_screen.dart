import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../widgets.dart';

/// La carte bouge sous un repère fixe : le centre devient le point de livraison.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.initial, this.title = 'Point de livraison'});

  final LatLng? initial;
  final String title;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _lome = LatLng(6.1375, 1.2123);

  final _map = MapController();
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial == null) WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  Future<void> _locate() async {
    setState(() => _locating = true);

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      if (mounted) _map.move(LatLng(position.latitude, position.longitude), 17);
    } catch (_) {
      if (mounted) showMessage(context, 'Position introuvable. Déplacez la carte vers votre adresse.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        alignment: Alignment.center,
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(initialCenter: widget.initial ?? _lome, initialZoom: widget.initial == null ? 13 : 17),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.superlivraison.superlivraison',
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 40),
            child: IgnorePointer(child: Icon(Icons.place, size: 44, color: Color(0xFFD9381E))),
          ),
          Positioned(
            right: 16,
            top: 16,
            child: FloatingActionButton.small(
              tooltip: 'Ma position',
              onPressed: _locating ? null : _locate,
              child: _locating
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_map.camera.center),
                child: const Text('Confirmer ce point'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
