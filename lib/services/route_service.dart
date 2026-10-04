import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'map_config.dart';

/// A road route between two points.
class RouteResult {
  final List<LatLng> points;
  final double metres, seconds;
  final bool onRoads; // false when we fell back to a straight line
  const RouteResult(this.points, this.metres, this.seconds, this.onRoads);

  /// Distance along the route from the point nearest to [pos] to the end.
  double remainingFrom(LatLng pos) {
    if (points.length < 2) return const Distance()(pos, points.last);
    const d = Distance();
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final x = d(pos, points[i]);
      if (x < bestD) {
        bestD = x;
        best = i;
      }
    }
    var rest = bestD;
    for (var i = best; i < points.length - 1; i++) {
      rest += d(points[i], points[i + 1]);
    }
    return rest;
  }

  /// How far [pos] is from the route line (roughly), in metres.
  double offRouteBy(LatLng pos) {
    const d = Distance();
    return points.fold(double.infinity, (m, p) => m < d(pos, p) ? m : d(pos, p));
  }

  double get metresPerSecond => seconds > 0 ? metres / seconds : MapConfig.fallbackMetresPerSecond;
}

/// Gets road routes from the routing server, with a small memory cache.
/// If the server can't be reached, returns a straight line so the map still works.
class RouteService {
  static final _cache = <String, RouteResult>{};

  static String _key(LatLng a, LatLng b) =>
      '${a.latitude.toStringAsFixed(4)},${a.longitude.toStringAsFixed(4)}>${b.latitude.toStringAsFixed(4)},${b.longitude.toStringAsFixed(4)}';

  static Future<RouteResult> route(LatLng a, LatLng b) async {
    final key = _key(a, b);
    final hit = _cache[key];
    if (hit != null) return hit;
    try {
      final url = Uri.parse('${MapConfig.routingUrl}/${a.longitude},${a.latitude};${b.longitude},${b.latitude}'
          '?overview=full&geometries=geojson');
      final res = await http.get(url, headers: {'User-Agent': 'Letea/1.0 (${MapConfig.appId})'}).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final r = (j['routes'] as List).first as Map<String, dynamic>;
        final coords = (r['geometry']['coordinates'] as List)
            .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
        if (coords.length >= 2) {
          final out = RouteResult(coords, (r['distance'] as num).toDouble(), (r['duration'] as num).toDouble(), true);
          if (_cache.length > 200) _cache.clear();
          return _cache[key] = out;
        }
      }
    } catch (_) {
      // No internet or routing server busy: fall through to a straight line.
    }
    final m = const Distance()(a, b);
    return RouteResult([a, b], m, m / MapConfig.fallbackMetresPerSecond, false);
  }
}

/// "12 min · 3.4 km" style label.
String etaLabel(double metres, double metresPerSecond) {
  final mins = (metres / metresPerSecond / 60).ceil();
  final km = metres >= 1000 ? '${(metres / 1000).toStringAsFixed(1)} km' : '${(metres / 10).round() * 10} m';
  if (metres < 60) return 'Arriving now';
  return '${mins < 1 ? 1 : mins} min · $km';
}
