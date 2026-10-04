import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart' show GeoPoint, Timestamp;

import '../models/models.dart';
import 'package:latlong2/latlong.dart';

import 'map_config.dart';
import 'route_service.dart';

/// In-memory backend for preview mode. Sample shops in Dar es Salaam, and a
/// sample rider (Juma) who collects and delivers orders on his own, so one
/// person can watch the full order flow on one phone. Data resets when the app closes.
class DemoStore {
  static final _changes = StreamController<void>.broadcast();
  static final Map<String, AppUser> users = {};
  static final List<Listing> listings = [];
  static final List<ShopOrder> orders = [];
  static final Map<String, String> _pins = {};
  static final _rnd = Random();
  static String? currentUid;
  static bool _seeded = false;

  static const riderJuma = 'demo-rider-juma';

  static GeoPoint pointFor(String area) {
    final p = MapConfig.areaPoint(area);
    return GeoPoint(p.latitude, p.longitude);
  }

  static void notify() => _changes.add(null);

  /// A live stream that re-reads [read] whenever preview data changes.
  static Stream<T> watch<T>(T Function() read) => Stream<T>.multi((c) {
        c.add(read());
        final sub = _changes.stream.listen((_) => c.add(read()));
        c.onCancel = sub.cancel;
      });

  static String newId(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_rnd.nextInt(999)}';

  static void seed() {
    if (_seeded) return;
    _seeded = true;
    void shop(String id, String name, String cat, String area, String phone, {bool verified = true}) {
      users[id] = AppUser(uid: id, phone: phone, provider: {'name': name, 'cat': cat, 'area': area, 'verified': verified});
    }

    shop('demo-p1', 'Kariakoo Mart', 'shopping', 'Kariakoo', '+255754000111');
    shop('demo-p2', 'Afya Plus Pharmacy', 'pharmacy', 'Upanga', '+255754000222');
    shop('demo-p3', 'Mama Ntilie Kitchen', 'food', 'Sinza', '+255754000333');
    shop('demo-p4', 'Fundi Bora', 'services', 'Kinondoni', '+255754000444');
    shop('demo-p5', 'Safi Laundry', 'services', 'Mikocheni', '+255754000555');
    users[riderJuma] = AppUser(uid: riderJuma, phone: '+255765111222', rider: {'name': 'Juma Said', 'vehicle': 'Boda', 'plate': 'MC 482 BKT', 'online': true});

    var n = 0;
    void item(String pid, String cat, String name, int price, String unit, String desc, {String type = 'product', bool rx = false}) {
      final p = users[pid]!.provider!;
      listings.add(Listing(
        id: 'demo-l${n++}', providerId: pid, providerName: p['name'], area: p['area'], cat: cat,
        name: name, unit: unit, desc: desc, type: type, price: price, rx: rx, active: true,
      ));
    }

    item('demo-p1', 'shopping', 'Cooking oil 3L', 16500, 'bottle', 'Sunflower oil, sealed bottle.');
    item('demo-p1', 'shopping', 'Rice, Kyela 5kg', 17000, 'bag', 'Aromatic Kyela rice.');
    item('demo-p1', 'shopping', 'Drinking water 12 × 500ml', 7500, 'pack', 'Bottled drinking water.');
    item('demo-p1', 'shopping', 'Sugar 2kg', 6200, 'pack', 'White sugar.');
    item('demo-p2', 'pharmacy', 'Paracetamol 500mg', 2000, 'strip of 10', 'Pain and fever relief.');
    item('demo-p2', 'pharmacy', 'Amoxicillin 500mg', 6500, 'pack', 'Antibiotic. Prescription needed.', rx: true);
    item('demo-p2', 'pharmacy', 'ORS sachets', 1500, '5 sachets', 'Oral rehydration salts.');
    item('demo-p3', 'food', 'Pilau ya nyama', 8000, 'plate', 'Spiced rice with beef and kachumbari.');
    item('demo-p3', 'food', 'Chipsi mayai', 5000, 'plate', 'Chips omelette with salad.');
    item('demo-p4', 'services', 'Plumbing repair', 25000, 'visit', 'Leaks, taps, toilets. Parts charged separately.', type: 'service');
    item('demo-p4', 'services', 'Electrical fault check', 30000, 'visit', 'Sockets, wiring, breakers.', type: 'service');
    item('demo-p5', 'services', 'Wash & iron', 3000, 'kg', 'Pickup and return within 48 hours.', type: 'service');
  }

  // ---------------- orders ----------------
  static ShopOrder? find(String id) => orders.where((o) => o.id == id).firstOrNull;

  static void replace(ShopOrder o) {
    final i = orders.indexWhere((x) => x.id == o.id);
    if (i >= 0) orders[i] = o;
    notify();
  }

  static ShopOrder copy(ShopOrder o, {
    String? status, String? payStatus, String? riderId, String? riderName, String? riderPhone,
    String? riderPlate, GeoPoint? riderLoc, String? stamp,
  }) {
    final times = Map<String, Timestamp>.from(o.times);
    if (stamp != null) times[stamp] = Timestamp.now();
    return ShopOrder(
      id: o.id, code: o.code, customerId: o.customerId, customerName: o.customerName,
      customerPhone: o.customerPhone, providerId: o.providerId, providerName: o.providerName,
      providerPhone: o.providerPhone, pickupArea: o.pickupArea, dropoffAddress: o.dropoffAddress,
      kind: o.kind, status: status ?? o.status, payMethod: o.payMethod, payStatus: payStatus ?? o.payStatus,
      riderId: riderId ?? o.riderId, riderName: riderName ?? o.riderName, riderPhone: riderPhone ?? o.riderPhone,
      riderPlate: riderPlate ?? o.riderPlate, rxUrl: o.rxUrl, pickup: o.pickup, dropoff: o.dropoff, riderLoc: riderLoc ?? o.riderLoc,
      items: o.items, subtotal: o.subtotal, fee: o.fee, times: times,
    );
  }

  static List<String> createOrders(String uid, List<Map<String, dynamic>> items, String address, double? lat, double? lng, String payMethod) {
    final me = users[uid];
    final customer = me?.customer;
    if (customer == null) throw StateError('Set up your customer account first.');
    final groups = <String, List<(Listing, int)>>{};
    for (final i in items) {
      final l = listings.firstWhere((x) => x.id == i['listingId'] && x.active,
          orElse: () => throw StateError('Something in your cart is no longer available.'));
      groups.putIfAbsent(l.providerId, () => []).add((l, i['qty'] as int));
    }
    final ids = <String>[];
    for (final e in groups.entries) {
      final p = users[e.key]?.provider ?? {};
      final kind = e.value.any((x) => !x.$1.isService) ? 'delivery' : 'service';
      final id = newId('order');
      final o = ShopOrder(
        id: id,
        code: 'LT-${(1000 + _rnd.nextInt(9000))}',
        customerId: uid, customerName: customer['name'] ?? '', customerPhone: me!.phone,
        providerId: e.key, providerName: p['name'] ?? '', providerPhone: users[e.key]?.phone ?? '',
        pickupArea: p['area'] ?? 'Kariakoo', dropoffAddress: address,
        pickup: p['lat'] is num ? GeoPoint((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()) : pointFor(p['area'] ?? 'Kariakoo'),
        dropoff: lat != null && lng != null ? GeoPoint(lat, lng) : pointFor(customer['area'] ?? 'Mikocheni'),
        kind: kind, status: 'placed', payMethod: payMethod, payStatus: 'unpaid',
        items: [for (final x in e.value) OrderItem(x.$1.name, x.$1.price, x.$2)],
        subtotal: e.value.fold(0, (a, x) => a + x.$1.price * x.$2),
        fee: kind == 'delivery' ? 2000 : 0,
        times: {'placed': Timestamp.now()},
      );
      orders.insert(0, o);
      _pins[id] = '${1000 + _rnd.nextInt(9000)}';
      ids.add(id);
      // Sample shops run themselves; your own shop waits for you.
      if (e.key != uid) _autoProvider(id);
    }
    notify();
    return ids;
  }

  static String? pin(String id) => _pins[id];

  static void setStatus(String id, String status) {
    final o = find(id);
    if (o == null) return;
    replace(copy(o, status: status, stamp: status));
    if (status == 'ready') _later(8, () => _autoRider(id));
  }

  static bool takeJob(String id, String riderId, Map<String, dynamic> rider, String phone) {
    final o = find(id);
    if (o == null || o.status != 'ready' || o.riderId != null) return false;
    replace(copy(o, status: 'assigned', riderId: riderId, riderName: rider['name'], riderPhone: phone, riderPlate: rider['plate'] ?? '', stamp: 'assigned'));
    return true;
  }

  static void confirm(String id, String pin) {
    final o = find(id);
    if (o == null || o.status != 'onway') throw StateError('This order is not on the way yet.');
    if (_pins[id] != pin) throw StateError('That PIN is wrong. Ask the customer to check their order screen.');
    replace(copy(o, status: 'delivered', stamp: 'delivered', payStatus: o.payMethod == 'cash' ? 'paid' : null));
  }

  // ---------------- the sample shop and rider ----------------
  static void _later(int seconds, void Function() f) => Future.delayed(Duration(seconds: seconds), f);

  static void _autoProvider(String id) {
    _later(4, () {
      final o = find(id);
      if (o?.status != 'placed') return;
      setStatus(id, 'accepted');
      _later(6, () {
        final o = find(id);
        if (o?.status != 'accepted') return;
        if (o!.isService) {
          setStatus(id, 'onway');
          _later(30, () {
            if (find(id)?.status == 'onway') replace(copy(find(id)!, status: 'delivered', stamp: 'delivered'));
          });
        } else {
          setStatus(id, 'ready');
        }
      });
    });
  }

  /// Juma takes the job, unless you are registered as a rider and online:
  /// then the job waits for you in the Jobs tab.
  static void _autoRider(String id) {
    final o = find(id);
    if (o == null || o.status != 'ready' || o.riderId != null) return;
    final meRider = currentUid == null ? null : users[currentUid]?.rider;
    if (meRider != null && meRider['online'] == true) return;
    final j = users[riderJuma]!;
    takeJob(id, riderJuma, j.rider!, j.phone);
    runRider(id, auto: true);
  }

  /// Moves the rider along real roads: first from nearby to the shop, then
  /// from the shop to the customer. With [auto] the rider also picks up and
  /// delivers by himself (Juma). Without it (you are the rider) the bike
  /// waits at the shop until you tap "Picked up", and at the door for the PIN.
  static final Set<String> _riding = {};
  static Future<void> runRider(String id, {bool auto = false}) async {
    if (_riding.contains(id)) return;
    final o = find(id);
    if (o == null) return;
    _riding.add(id);
    final shop = o.pickup ?? pointFor(o.pickupArea);
    final home = o.dropoff ?? pointFor('Mikocheni');
    final shopLL = LatLng(shop.latitude, shop.longitude), homeLL = LatLng(home.latitude, home.longitude);
    final startLL = o.riderLoc != null
        ? LatLng(o.riderLoc!.latitude, o.riderLoc!.longitude)
        : LatLng(shop.latitude + 0.008, shop.longitude - 0.006); // about 1 km away
    final toShop = await RouteService.route(startLL, shopLL);
    final toHome = await RouteService.route(shopLL, homeLL);
    final approach = _Path(toShop.points), delivery = _Path(toHome.points);
    var a = 0.0, d = 0.0;
    var waitedAtShop = 0;
    Timer.periodic(const Duration(seconds: 1), (t) {
      final cur = find(id);
      if (cur == null || !cur.isOpen) {
        t.cancel();
        _riding.remove(id);
        return;
      }
      if (cur.status == 'assigned') {
        if (a < approach.length) {
          a = min(approach.length, a + approach.length / 20); // about 20 s to the shop
          replace(copy(cur, riderLoc: approach.at(a)));
        } else if (auto && ++waitedAtShop >= 3) {
          replace(copy(cur, status: 'onway', stamp: 'onway', riderLoc: shop));
        }
      } else if (cur.status == 'onway') {
        if (d < delivery.length) {
          d = min(delivery.length, d + delivery.length / 40); // about 40 s to the door
          replace(copy(cur, riderLoc: delivery.at(d)));
        } else if (auto) {
          t.cancel();
          _riding.remove(id);
          _later(3, () {
            final c = find(id);
            if (c?.status == 'onway') replace(copy(c!, status: 'delivered', stamp: 'delivered', payStatus: c.payMethod == 'cash' ? 'paid' : null));
          });
        }
      }
    });
  }
}

/// A road line you can walk along by distance.
class _Path {
  final List<LatLng> pts;
  final List<double> cum = [0];
  _Path(this.pts) {
    const dist = Distance();
    for (var i = 1; i < pts.length; i++) {
      cum.add(cum.last + dist(pts[i - 1], pts[i]));
    }
  }
  double get length => cum.last;

  GeoPoint at(double metres) {
    if (pts.length == 1 || metres <= 0) return GeoPoint(pts.first.latitude, pts.first.longitude);
    for (var i = 1; i < pts.length; i++) {
      if (cum[i] >= metres) {
        final seg = cum[i] - cum[i - 1];
        final f = seg == 0 ? 0.0 : (metres - cum[i - 1]) / seg;
        return GeoPoint(
          pts[i - 1].latitude + (pts[i].latitude - pts[i - 1].latitude) * f,
          pts[i - 1].longitude + (pts[i].longitude - pts[i - 1].longitude) * f,
        );
      }
    }
    return GeoPoint(pts.last.latitude, pts.last.longitude);
  }
}
