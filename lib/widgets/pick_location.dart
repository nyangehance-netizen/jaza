import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/location_service.dart';
import '../services/map_config.dart';

/// Full-screen map to choose an exact spot: move the map so the pin sits on
/// your door (or your shop), then confirm. Returns a [LatLng].
class PickLocationScreen extends StatefulWidget {
  final String title;
  final LatLng? initial;
  const PickLocationScreen({super.key, required this.title, this.initial});

  @override
  State<PickLocationScreen> createState() => _PickLocationScreenState();
}

class _PickLocationScreenState extends State<PickLocationScreen> {
  final _map = MapController();
  late LatLng _center = widget.initial ?? const LatLng(MapConfig.darLat, MapConfig.darLng);
  bool _locating = false;

  Future<void> _myLocation() async {
    setState(() => _locating = true);
    final p = await LocationService.current();
    if (!mounted) return;
    setState(() => _locating = false);
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Allow location access, or move the map by hand.')));
      return;
    }
    _center = LatLng(p.latitude, p.longitude);
    _map.move(_center, 17);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: widget.initial == null ? 12 : 17,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onPositionChanged: (camera, _) => _center = camera.center,
          ),
          children: [
            TileLayer(urlTemplate: MapConfig.tileUrl, userAgentPackageName: MapConfig.appId, maxZoom: 19),
            RichAttributionWidget(attributions: [
              TextSourceAttribution(MapConfig.attribution,
                  onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'), mode: LaunchMode.externalApplication)),
            ]),
          ],
        ),
        // The pin stays in the middle; the map moves underneath it.
        IgnorePointer(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 44),
              child: Icon(Icons.location_on, size: 48, color: cs.primary, shadows: const [Shadow(blurRadius: 6, color: Color(0x66000000))]),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: 12,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Move the map until the pin is exactly on the spot.', style: TextStyle(color: cs.onSurface)),
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 100,
          child: FloatingActionButton.small(
            heroTag: 'locate',
            onPressed: _locating ? null : _myLocation,
            tooltip: 'My location',
            child: _locating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: SafeArea(
            top: false,
            child: FilledButton(onPressed: () => Navigator.pop(context, _center), child: const Text('Use this spot')),
          ),
        ),
      ]),
    );
  }
}
