import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/map_config.dart';
import '../services/route_service.dart';

LatLng? toLatLng(dynamic g) => g == null ? null : LatLng(g.latitude as double, g.longitude as double);

/// The shop's position: its pinned location, or the centre of its area.
LatLng shopPoint(ShopOrder o) => toLatLng(o.pickup) ?? MapConfig.areaPoint(o.pickupArea);

/// Live delivery map used by the customer, the shop and the rider.
/// Shows the shop, the customer's door, the rider moving, the road route and
/// the time left. Updates by itself whenever the order changes.
class DeliveryMap extends StatefulWidget {
  final ShopOrder order;
  final double height;

  /// Rider view: adds a button that opens turn-by-turn directions.
  final bool forRider;
  const DeliveryMap({super.key, required this.order, this.height = 260, this.forRider = false});

  @override
  State<DeliveryMap> createState() => _DeliveryMapState();
}

class _DeliveryMapState extends State<DeliveryMap> {
  final _map = MapController();
  bool _ready = false, _fetching = false;
  RouteResult? _active, _next;
  String _legKey = '';

  ShopOrder get o => widget.order;
  LatLng get _shop => shopPoint(o);
  LatLng? get _home => toLatLng(o.dropoff);
  LatLng? get _rider => toLatLng(o.riderLoc);

  /// Where the rider is heading now: the shop until pickup, then the customer.
  LatLng? get _target => switch (o.status) {
        'assigned' => _shop,
        'onway' => _home,
        _ => null,
      };

  @override
  void initState() {
    super.initState();
    _updateRoutes();
  }

  @override
  void didUpdateWidget(DeliveryMap old) {
    super.didUpdateWidget(old);
    _updateRoutes();
    final r = _rider;
    if (_ready && r != null && !_map.camera.visibleBounds.contains(r)) _fitAll();
  }

  Future<void> _updateRoutes() async {
    if (_fetching) return;
    final home = _home;
    final target = _target;
    final from = _rider ?? _shop;
    final key = '${o.status}|${target?.latitude},${target?.longitude}';
    final off = _active != null && _rider != null && _active!.offRouteBy(_rider!) > 250;
    final needActive = target != null && (key != _legKey || _active == null || off);
    final needNext = home != null && _next == null;
    if (!needActive && !needNext && key == _legKey) return;
    _fetching = true;
    try {
      final active = needActive ? await RouteService.route(from, target) : (target == null ? null : _active);
      final next = needNext ? await RouteService.route(_shop, home) : _next;
      if (!mounted) return;
      setState(() {
        _active = active;
        _next = next;
        _legKey = key;
      });
    } finally {
      _fetching = false;
    }
  }

  List<LatLng> get _allPoints => [_shop, if (_home != null) _home!, if (_rider != null) _rider!];

  void _fitAll() {
    final pts = _allPoints;
    if (pts.length == 1) {
      _map.move(pts.first, 15);
      return;
    }
    _map.fitCamera(CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.fromLTRB(40, 70, 40, 40), maxZoom: 16));
  }

  String get _headline {
    final r = _rider, a = _active;
    switch (o.status) {
      case 'placed':
      case 'accepted':
        return 'Shop is preparing the order';
      case 'ready':
        return 'Finding a rider';
      case 'assigned':
        return r != null && a != null ? 'Rider to shop · ${etaLabel(a.remainingFrom(r), a.metresPerSecond)}' : 'Rider heading to the shop';
      case 'onway':
        return r != null && a != null ? 'Arriving · ${etaLabel(a.remainingFrom(r), a.metresPerSecond)}' : 'On the way';
      case 'delivered':
        return 'Delivered';
      default:
        return '';
    }
  }

  Future<void> _directions() async {
    final t = _target ?? _shop;
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${t.latitude},${t.longitude}&travelmode=driving');
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open directions. Install Google Maps or another maps app.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = _rider, home = _home;
    final pts = _allPoints;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: widget.height,
        child: Stack(children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: pts.first,
              initialZoom: 14,
              initialCameraFit: pts.length > 1
                  ? CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.fromLTRB(40, 70, 40, 40), maxZoom: 16)
                  : null,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              onMapReady: () => _ready = true,
            ),
            children: [
              TileLayer(urlTemplate: MapConfig.tileUrl, userAgentPackageName: MapConfig.appId, maxZoom: 19),
              PolylineLayer(polylines: [
                if (_next != null && o.status != 'onway')
                  Polyline(points: _next!.points, strokeWidth: 4, color: cs.secondary, pattern: const StrokePattern.dotted()),
                if (_active != null && o.isOpen) Polyline(points: _active!.points, strokeWidth: 5, color: cs.primary),
              ]),
              MarkerLayer(markers: [
                Marker(point: _shop, width: 40, height: 40, child: _Pin(icon: Icons.storefront, color: cs.secondary, onColor: cs.onSecondary)),
                if (home != null) Marker(point: home, width: 40, height: 40, child: _Pin(icon: Icons.home, color: cs.tertiary, onColor: cs.onTertiary)),
                if (r != null && o.isOpen) Marker(point: r, width: 46, height: 46, child: _Pin(icon: Icons.two_wheeler, color: cs.primary, onColor: cs.onPrimary, big: true)),
              ]),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(MapConfig.attribution,
                      onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'), mode: LaunchMode.externalApplication)),
                ],
              ),
            ],
          ),
          Positioned(
            left: 10,
            top: 10,
            right: 60,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [BoxShadow(blurRadius: 6, color: Color(0x33000000))],
                ),
                child: Text(_headline, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          Positioned(
            right: 10,
            top: 10,
            child: IconButton.filledTonal(onPressed: _fitAll, icon: const Icon(Icons.center_focus_strong), tooltip: 'Show everyone'),
          ),
          if (widget.forRider && _target != null)
            Positioned(
              right: 10,
              bottom: 26,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: _directions,
                icon: const Icon(Icons.navigation),
                label: Text(o.status == 'assigned' ? 'Directions to shop' : 'Directions to customer'),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  final IconData icon;
  final Color color, onColor;
  final bool big;
  const _Pin({required this.icon, required this.color, required this.onColor, this.big = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Color(0x55000000))],
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: onColor, size: big ? 24 : 20),
    );
  }
}
