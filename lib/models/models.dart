import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

final _tsh = NumberFormat.decimalPattern('en_US');
String tsh(num n) => 'TSh ${_tsh.format(n.round())}';

const areas = [
  'Kariakoo', 'Mikocheni', 'Masaki', 'Sinza', 'Mbezi Beach', 'Upanga',
  'Kinondoni', 'Tegeta', 'Ubungo', 'Kigamboni', 'Mbagala', 'Temeke',
];

const categories = {
  'shopping': 'Shopping',
  'pharmacy': 'Pharmacy',
  'food': 'Food',
  'services': 'Services',
  'parcel': 'Parcels',
};

enum Role { customer, provider, rider }

String roleLabel(Role r) => switch (r) {
      Role.customer => 'Customer',
      Role.provider => 'Provider',
      Role.rider => 'Rider',
    };

/// users/{uid}. One account can hold any of the three roles.
class AppUser {
  final String uid;
  final String phone;
  final Map<String, dynamic>? customer; // name, area
  final Map<String, dynamic>? provider; // name, cat, area, verified
  final Map<String, dynamic>? rider; // name, vehicle, plate, online

  AppUser({required this.uid, required this.phone, this.customer, this.provider, this.rider});

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return AppUser(
      uid: d.id,
      phone: m['phone'] ?? '',
      customer: m['customer'],
      provider: m['provider'],
      rider: m['rider'],
    );
  }

  Map<String, dynamic>? profile(Role r) => switch (r) {
        Role.customer => customer,
        Role.provider => provider,
        Role.rider => rider,
      };

  List<Role> get roles => Role.values.where((r) => profile(r) != null).toList();
}

/// listings/{id}
class Listing {
  final String id, providerId, providerName, area, cat, name, unit, desc, type;
  final int price;
  final bool rx, active;
  final String? imageUrl;

  /// Photos of the product or service. The first one is the cover.
  final List<String> images;

  Listing({
    required this.id, required this.providerId, required this.providerName,
    required this.area, required this.cat, required this.name, required this.unit,
    required this.desc, required this.type, required this.price,
    required this.rx, required this.active, this.imageUrl, this.images = const [],
  });

  bool get isService => type == 'service';

  /// All photos, including the older single-photo field.
  List<String> get photos => images.isNotEmpty ? images : [if (imageUrl != null) imageUrl!];
  String? get cover => photos.isEmpty ? null : photos.first;

  Listing copyWith({String? name, String? cat, String? unit, String? desc, String? type, int? price, bool? rx, bool? active, List<String>? images}) =>
      Listing(
        id: id, providerId: providerId, providerName: providerName, area: area,
        cat: cat ?? this.cat, name: name ?? this.name, unit: unit ?? this.unit, desc: desc ?? this.desc,
        type: type ?? this.type, price: price ?? this.price, rx: rx ?? this.rx, active: active ?? this.active,
        imageUrl: images != null ? (images.isEmpty ? null : images.first) : imageUrl,
        images: images ?? this.images,
      );

  factory Listing.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    return Listing(
      id: d.id,
      providerId: m['providerId'],
      providerName: m['providerName'] ?? '',
      area: m['area'] ?? '',
      cat: m['cat'] ?? 'shopping',
      name: m['name'] ?? '',
      unit: m['unit'] ?? 'item',
      desc: m['desc'] ?? '',
      type: m['type'] ?? 'product',
      price: ((m['price'] ?? 0) as num).toInt(),
      rx: m['rx'] == true,
      active: m['active'] != false,
      imageUrl: m['imageUrl'],
      images: ((m['images'] as List?) ?? const []).whereType<String>().toList(),
    );
  }
}

class OrderItem {
  final String name;
  final int price, qty;
  OrderItem(this.name, this.price, this.qty);
  factory OrderItem.fromMap(Map<String, dynamic> m) =>
      OrderItem(m['name'], (m['price'] as num).toInt(), (m['qty'] as num).toInt());
}

/// orders/{id}. Created only by the createOrders Cloud Function.
class ShopOrder {
  final String id, code, customerId, customerName, customerPhone;
  final String providerId, providerName, providerPhone, pickupArea, dropoffAddress;
  final String kind, status, payMethod, payStatus;
  final String? riderId, riderName, riderPhone, riderPlate, rxUrl;
  final GeoPoint? pickup, dropoff, riderLoc;
  final List<OrderItem> items;
  final int subtotal, fee;
  final Map<String, Timestamp> times;

  ShopOrder({
    required this.id, required this.code, required this.customerId, required this.customerName,
    required this.customerPhone, required this.providerId, required this.providerName,
    required this.providerPhone, required this.pickupArea, required this.dropoffAddress,
    required this.kind, required this.status, required this.payMethod, required this.payStatus,
    this.riderId, this.riderName, this.riderPhone, this.riderPlate, this.rxUrl, this.pickup, this.dropoff, this.riderLoc,
    required this.items, required this.subtotal, required this.fee, required this.times,
  });

  int get total => subtotal + fee;
  bool get isService => kind == 'service';
  bool get isOpen => status != 'delivered' && status != 'cancelled';

  factory ShopOrder.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    return ShopOrder(
      id: d.id,
      code: m['code'] ?? '',
      customerId: m['customerId'],
      customerName: m['customerName'] ?? '',
      customerPhone: m['customerPhone'] ?? '',
      providerId: m['providerId'],
      providerName: m['providerName'] ?? '',
      providerPhone: m['providerPhone'] ?? '',
      pickupArea: m['pickupArea'] ?? '',
      dropoffAddress: m['dropoffAddress'] ?? '',
      pickup: m['pickup'],
      dropoff: m['dropoff'],
      kind: m['kind'] ?? 'delivery',
      status: m['status'] ?? 'placed',
      payMethod: m['payMethod'] ?? 'cash',
      payStatus: m['payStatus'] ?? 'unpaid',
      riderId: m['riderId'],
      riderName: m['riderName'],
      riderPhone: m['riderPhone'],
      riderPlate: m['riderPlate'],
      riderLoc: m['riderLoc'],
      rxUrl: m['rxUrl'],
      items: ((m['items'] ?? []) as List)
          .map((e) => OrderItem.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      subtotal: ((m['subtotal'] ?? 0) as num).toInt(),
      fee: ((m['fee'] ?? 0) as num).toInt(),
      times: {
        for (final e in Map<String, dynamic>.from(m['times'] ?? {}).entries)
          if (e.value is Timestamp) e.key: e.value as Timestamp, // pending server times are skipped
      },
    );
  }
}

const deliverySteps = [
  ('placed', 'Order placed'),
  ('accepted', 'Shop confirmed'),
  ('ready', 'Packed, waiting for rider'),
  ('assigned', 'Rider assigned'),
  ('onway', 'On the way'),
  ('delivered', 'Delivered'),
];

const serviceSteps = [
  ('placed', 'Booking sent'),
  ('accepted', 'Provider confirmed'),
  ('onway', 'Provider on the way'),
  ('delivered', 'Job completed'),
];

List<(String, String)> stepsFor(ShopOrder o) => o.isService ? serviceSteps : deliverySteps;

String statusLabel(ShopOrder o) {
  if (o.status == 'cancelled') return 'Declined';
  if (o.status == 'placed') return 'New';
  return stepsFor(o).firstWhere((s) => s.$1 == o.status, orElse: () => ('', o.status)).$2;
}
