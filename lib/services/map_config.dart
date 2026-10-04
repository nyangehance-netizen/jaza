import 'package:latlong2/latlong.dart';

/// Map and routing settings, in one place so they are easy to change.
///
/// The free OpenStreetMap servers are fine for testing and a small launch,
/// but their rules ask busy apps to use a paid provider. When Letea grows,
/// sign up with a map tile provider (for example MapTiler, Stadia Maps or
/// Thunderforest) and a routing provider, then change the two URLs below.
class MapConfig {
  /// Street map pictures. {z}/{x}/{y} are filled in by the map.
  static const tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Road routes (OSRM format). The public demo server is for testing only.
  static const routingUrl = 'https://router.project-osrm.org/route/v1/driving';

  /// Identifies the app to the map servers, as their rules require.
  static const appId = 'com.letea.letea';

  static const attribution = 'OpenStreetMap contributors';

  /// Centre of Dar es Salaam, used before we know anyone's location.
  static const darLat = -6.7924, darLng = 39.2083;

  /// Average boda speed in city traffic, used when a road route is not available.
  static const fallbackMetresPerSecond = 5.5; // about 20 km/h

  /// Rough centre points of Dar es Salaam areas, used when a shop or customer
  /// hasn't pinned an exact spot yet.
  static const _areas = {
    'Kariakoo': (-6.8190, 39.2740), 'Upanga': (-6.8090, 39.2860), 'Sinza': (-6.7790, 39.2230),
    'Kinondoni': (-6.7720, 39.2550), 'Mikocheni': (-6.7600, 39.2500), 'Masaki': (-6.7500, 39.2800),
    'Mbezi Beach': (-6.7200, 39.2150), 'Tegeta': (-6.6680, 39.2080), 'Ubungo': (-6.7900, 39.2050),
    'Kigamboni': (-6.8500, 39.3100), 'Mbagala': (-6.9000, 39.2700), 'Temeke': (-6.8600, 39.2550),
  };

  static LatLng areaPoint(String area) {
    final c = _areas[area] ?? (darLat, darLng);
    return LatLng(c.$1, c.$2);
  }
}
