import 'package:flutter/foundation.dart';

import '../models/models.dart';

class CartLine {
  final Listing listing;
  int qty;
  CartLine(this.listing, this.qty);
}

/// The cart lives on the phone until the order is placed.
class Cart extends ChangeNotifier {
  final Map<String, CartLine> _lines = {};

  List<CartLine> get lines => _lines.values.toList();
  int get count => _lines.values.fold(0, (a, l) => a + l.qty);
  bool get isEmpty => _lines.isEmpty;
  bool get needsPrescription => _lines.values.any((l) => l.listing.rx);

  /// Grouped by provider: each provider becomes its own order.
  Map<String, List<CartLine>> get byProvider {
    final m = <String, List<CartLine>>{};
    for (final l in _lines.values) {
      m.putIfAbsent(l.listing.providerId, () => []).add(l);
    }
    return m;
  }

  static const deliveryFee = 2000;

  int get subtotal => _lines.values.fold(0, (a, l) => a + l.listing.price * l.qty);
  int get fees => byProvider.values.where((g) => g.any((l) => !l.listing.isService)).length * deliveryFee;
  int get total => subtotal + fees;

  void add(Listing l) {
    _lines.update(l.id, (x) => x..qty += 1, ifAbsent: () => CartLine(l, 1));
    notifyListeners();
  }

  void remove(Listing l) {
    final x = _lines[l.id];
    if (x == null) return;
    x.qty -= 1;
    if (x.qty <= 0) _lines.remove(l.id);
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }

  List<Map<String, dynamic>> toRequest() =>
      _lines.values.map((l) => {'listingId': l.listing.id, 'qty': l.qty}).toList();
}
