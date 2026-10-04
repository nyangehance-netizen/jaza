import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'app_mode.dart';
import 'db.dart';
import 'demo_store.dart';

/// Shares the rider's GPS position on an active trip so the customer can
/// watch the rider move on the map.
class LocationService {
  static StreamSubscription<Position>? _sub;
  static String? _orderId;

  static Future<String?> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Turn on location (GPS) so customers can follow the delivery.';
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      return 'Letea needs location access while you deliver. Allow it in your phone settings.';
    }
    return null;
  }

  static Future<Position?> current() async {
    if (await ensurePermission() != null) return null;
    return Geolocator.getCurrentPosition();
  }

  /// Sends a new position about every 50 metres (not every second) to save data and battery.
  static Future<String?> startSharing(String orderId) async {
    if (AppMode.preview) {
      DemoStore.runRider(orderId); // preview: the bike moves along real roads by itself
      return null;
    }
    final err = await ensurePermission();
    if (err != null) return err;
    if (_orderId == orderId) return null;
    await stopSharing();
    _orderId = orderId;
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 50),
    ).listen((pos) => Db.updateRiderLocation(orderId, pos.latitude, pos.longitude));
    return null;
  }

  static Future<void> stopSharing() async {
    await _sub?.cancel();
    _sub = null;
    _orderId = null;
  }
}
