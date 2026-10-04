import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

import '../models/models.dart';
import 'app_mode.dart';
import 'demo_store.dart';

/// All reads and writes in one place. Security rules (firestore.rules) decide
/// what each person may actually do; money and PIN checks run in Cloud Functions.
class Db {
  static FirebaseFirestore get _fs => FirebaseFirestore.instance;
  static FirebaseFunctions get _fn => FirebaseFunctions.instanceFor(region: 'europe-west1');
  static FirebaseStorage get _st => FirebaseStorage.instance;
  static bool get _pv => AppMode.preview;
  static Future<void> _tick() => Future.delayed(const Duration(milliseconds: 250));

  // ---------- Users ----------
  static Stream<AppUser?> user(String uid) => _pv ? DemoStore.watch(() => DemoStore.users[uid]) : _fs
      .doc('users/$uid')
      .snapshots()
      .map((d) => d.exists ? AppUser.fromDoc(d) : null);

  static Future<void> saveRole(String uid, String phone, Role role, Map<String, dynamic> data) async {
    if (_pv) {
      await _tick();
      final u = DemoStore.users[uid];
      DemoStore.users[uid] = AppUser(
        uid: uid, phone: phone,
        customer: role == Role.customer ? data : u?.customer,
        provider: role == Role.provider ? data : u?.provider,
        rider: role == Role.rider ? data : u?.rider,
      );
      DemoStore.notify();
      return;
    }
    return _fs.doc('users/$uid').set({
        'phone': phone,
        role.name: data,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
  }

  static Future<void> setRiderOnline(String uid, bool online) async {
    if (_pv) {
      final u = DemoStore.users[uid]!;
      DemoStore.users[uid] = AppUser(uid: uid, phone: u.phone, customer: u.customer, provider: u.provider, rider: {...?u.rider, 'online': online});
      DemoStore.notify();
      return;
    }
    await _fs.doc('users/$uid').update({'rider.online': online});
  }

  // ---------- Listings ----------
  static Stream<List<Listing>> activeListings() => _pv ? DemoStore.watch(() => DemoStore.listings.where((l) => l.active).toList()) : _fs
      .collection('listings')
      .where('active', isEqualTo: true)
      .orderBy('createdAt', descending: true)
      .limit(300)
      .snapshots()
      .map((s) => s.docs.map(Listing.fromDoc).toList());

  static Stream<List<Listing>> myListings(String providerId) => _pv ? DemoStore.watch(() => DemoStore.listings.where((l) => l.providerId == providerId).toList()) : _fs
      .collection('listings')
      .where('providerId', isEqualTo: providerId)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(Listing.fromDoc).toList());

  static Future<void> addListing(Map<String, dynamic> data, {File? image}) async {
    if (_pv) {
      await _tick();
      DemoStore.listings.insert(0, Listing(
        id: DemoStore.newId('listing'), providerId: data['providerId'], providerName: data['providerName'] ?? '',
        area: data['area'] ?? '', cat: data['cat'], name: data['name'], unit: data['unit'], desc: data['desc'] ?? '',
        type: data['type'], price: data['price'], rx: data['rx'] == true, active: true,
      ));
      DemoStore.notify();
      return;
    }
    final ref = _fs.collection('listings').doc();
    String? url;
    if (image != null) {
      final up = await _st.ref('listings/${data['providerId']}/${ref.id}.jpg').putFile(image);
      url = await up.ref.getDownloadURL();
    }
    await ref.set({...data, 'imageUrl': url, 'active': true, 'createdAt': FieldValue.serverTimestamp()});
  }

  static Future<void> setListingActive(String id, bool active) async {
    if (_pv) {
      final i = DemoStore.listings.indexWhere((l) => l.id == id);
      final l = DemoStore.listings[i];
      DemoStore.listings[i] = Listing(
        id: l.id, providerId: l.providerId, providerName: l.providerName, area: l.area, cat: l.cat, name: l.name,
        unit: l.unit, desc: l.desc, type: l.type, price: l.price, rx: l.rx, active: active, imageUrl: l.imageUrl,
      );
      DemoStore.notify();
      return;
    }
    await _fs.doc('listings/$id').update({'active': active});
  }

  static Future<void> deleteListing(String id) async {
    if (_pv) {
      DemoStore.listings.removeWhere((l) => l.id == id);
      DemoStore.notify();
      return;
    }
    await _fs.doc('listings/$id').delete();
  }

  // ---------- Orders ----------
  static Stream<List<ShopOrder>> _orders(Query<Map<String, dynamic>> q) =>
      q.snapshots().map((s) => s.docs.map(ShopOrder.fromDoc).toList());

  static Stream<List<ShopOrder>> customerOrders(String uid) => _pv ? DemoStore.watch(() => DemoStore.orders.where((o) => o.customerId == uid).toList()) : _orders(_fs
      .collection('orders')
      .where('customerId', isEqualTo: uid)
      .orderBy('times.placed', descending: true)
      .limit(50));

  static Stream<List<ShopOrder>> providerOrders(String uid) => _pv ? DemoStore.watch(() => DemoStore.orders.where((o) => o.providerId == uid).toList()) : _orders(_fs
      .collection('orders')
      .where('providerId', isEqualTo: uid)
      .orderBy('times.placed', descending: true)
      .limit(100));

  static Stream<List<ShopOrder>> openJobs() => _pv ? DemoStore.watch(() => DemoStore.orders.where((o) => o.status == 'ready' && o.riderId == null && o.kind == 'delivery').toList()) : _orders(_fs
      .collection('orders')
      .where('status', isEqualTo: 'ready')
      .where('riderId', isNull: true)
      .limit(50));

  static Stream<List<ShopOrder>> riderOrders(String uid) => _pv ? DemoStore.watch(() => DemoStore.orders.where((o) => o.riderId == uid).toList()) : _orders(_fs
      .collection('orders')
      .where('riderId', isEqualTo: uid)
      .orderBy('times.placed', descending: true)
      .limit(100));

  static Stream<ShopOrder> order(String id) => _pv
      ? DemoStore.watch(() => DemoStore.find(id)).where((o) => o != null).map((o) => o!)
      : _fs.doc('orders/$id').snapshots().map(ShopOrder.fromDoc);

  /// The 4-digit PIN lives in a sub-document only the customer can read.
  static Future<String?> deliveryPin(String orderId) async {
    if (_pv) return DemoStore.pin(orderId);
    final d = await _fs.doc('orders/$orderId/private/secret').get();
    return d.data()?['pin'] as String?;
  }

  /// Provider and rider status changes. Rules only allow valid steps.
  static Future<void> setStatus(String orderId, String status) async {
    if (_pv) {
      await _tick();
      return DemoStore.setStatus(orderId, status);
    }
    return _fs.doc('orders/$orderId').update({
        'status': status,
        'times.$status': FieldValue.serverTimestamp(),
      });
  }

  /// First rider wins. The transaction fails if someone else already took it.
  static Future<bool> takeJob(String orderId, String riderId, Map<String, dynamic> rider, String phone) async {
    if (_pv) {
      await _tick();
      return DemoStore.takeJob(orderId, riderId, rider, phone);
    }
    final ref = _fs.doc('orders/$orderId');
    return _fs.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final m = snap.data();
      if (m == null || m['status'] != 'ready' || m['riderId'] != null) return false;
      tx.update(ref, {
        'riderId': riderId,
        'riderName': rider['name'],
        'riderPhone': phone,
        'riderPlate': rider['plate'] ?? '',
        'status': 'assigned',
        'times.assigned': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  static Future<void> updateRiderLocation(String orderId, double lat, double lng) async {
    if (_pv) {
      final o = DemoStore.find(orderId);
      if (o != null) DemoStore.replace(DemoStore.copy(o, riderLoc: GeoPoint(lat, lng)));
      return;
    }
    return _fs.doc('orders/$orderId').update({
        'riderLoc': GeoPoint(lat, lng),
        'riderLocAt': FieldValue.serverTimestamp(),
      });
  }

  // ---------- Cloud Functions ----------
  /// Prices are re-read on the server, so nobody can change them from the phone.
  static Future<List<String>> createOrders({
    required List<Map<String, dynamic>> items,
    required String address,
    double? lat,
    double? lng,
    required String payMethod,
    String? prescriptionPath,
  }) async {
    if (_pv) {
      await Future.delayed(const Duration(milliseconds: 700));
      return DemoStore.createOrders(DemoStore.currentUid!, items, address, lat, lng, payMethod);
    }
    final res = await _fn.httpsCallable('createOrders').call({
      'items': items,
      'address': address,
      'lat': lat,
      'lng': lng,
      'payMethod': payMethod,
      'prescriptionPath': prescriptionPath,
    });
    return List<String>.from(res.data['orderIds']);
  }

  static Future<void> confirmDelivery(String orderId, String pin) async {
    if (_pv) {
      await _tick();
      return DemoStore.confirm(orderId, pin);
    }
    await _fn.httpsCallable('confirmDelivery').call({'orderId': orderId, 'pin': pin});
  }

  static Future<void> startMobilePayment(String orderId, String phone) async {
    if (_pv) {
      // Preview: pretend the customer approved the payment prompt after a few seconds.
      Future.delayed(const Duration(seconds: 3), () {
        final o = DemoStore.find(orderId);
        if (o != null) DemoStore.replace(DemoStore.copy(o, payStatus: 'paid'));
      });
      return;
    }
    await _fn.httpsCallable('startMobilePayment').call({'orderId': orderId, 'phone': phone});
  }

  static Future<String> uploadPrescription(String uid, File file) async {
    if (_pv) return file.path;
    final path = 'prescriptions/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _st.ref(path).putFile(file);
    return path;
  }
}
