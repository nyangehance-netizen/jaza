import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/auth_service.dart';
import '../../services/db.dart';
import '../../services/location_service.dart';
import '../../state/cart.dart';
import '../../widgets/common.dart';
import '../auth/register_role.dart';
import 'track_screen.dart';

class CustomerHome extends StatefulWidget {
  final AppUser user;
  final Widget switcher;
  const CustomerHome({super.key, required this.user, required this.switcher});

  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    final pages = [
      _Browse(user: widget.user),
      _CartPage(user: widget.user, onPlaced: () => setState(() => _tab = 2)),
      _Orders(uid: widget.user.uid),
      _Account(user: widget.user),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(['Letea', 'Your cart', 'My orders', 'Account'][_tab]),
        actions: [widget.switcher],
      ),
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Badge(isLabelVisible: cart.count > 0, label: Text('${cart.count}'), child: const Icon(Icons.shopping_cart_outlined)),
            label: 'Cart',
          ),
          const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Orders'),
          const NavigationDestination(icon: Icon(Icons.person_outline), label: 'Account'),
        ],
      ),
    );
  }
}

// ---------------- Browse ----------------
class _Browse extends StatefulWidget {
  final AppUser user;
  const _Browse({required this.user});

  @override
  State<_Browse> createState() => _BrowseState();
}

class _BrowseState extends State<_Browse> {
  String _cat = 'all', _q = '';
  late final _listings = Db.activeListings();
  late final _orders = Db.customerOrders(widget.user.uid);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = widget.user.customer!;
    return CustomScrollView(slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        sliver: SliverList.list(children: [
          Text('Delivering to ${c['area']}', style: t.bodySmall),
          Text('Habari, ${(c['name'] as String).split(' ').first}', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          StreamBuilder<List<Order>>(
            stream: _orders,
            builder: (context, snap) {
              final open = (snap.data ?? []).where((o) => o.isOpen).toList();
              return Column(children: [
                for (final o in open)
                  Card(
                    color: Theme.of(context).colorScheme.primary,
                    child: ListTile(
                      textColor: Theme.of(context).colorScheme.onPrimary,
                      iconColor: Theme.of(context).colorScheme.onPrimary,
                      title: Text(o.status == 'onway' ? 'Your order is on the way' : statusLabel(o), style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(o.providerName),
                      trailing: const Text('Track →'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrackScreen(orderId: o.id))),
                    ),
                  ),
              ]);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search shops, medicine, fundis…'),
            onChanged: (v) => setState(() => _q = v.toLowerCase()),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final e in {'all': 'All', ...categories}.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(e.value), selected: _cat == e.key, onSelected: (_) => setState(() => _cat = e.key)),
                ),
            ]),
          ),
          const SizedBox(height: 10),
        ]),
      ),
      StreamBuilder<List<Listing>>(
        stream: _listings,
        builder: (context, snap) {
          if (!snap.hasData) return const SliverFillRemaining(child: Loading());
          final items = snap.data!
              .where((l) => _cat == 'all' || l.cat == _cat)
              .where((l) => _q.isEmpty || '${l.name} ${l.providerName} ${l.desc}'.toLowerCase().contains(_q))
              .toList();
          if (items.isEmpty) {
            return const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(icon: Icons.storefront_outlined, title: 'Nothing here yet', body: 'Try another word or category.'),
            );
          }
          return SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: .68),
              itemCount: items.length,
              itemBuilder: (_, i) => _ListingCard(items[i]),
            ),
          );
        },
      ),
    ]);
  }
}

class _ListingCard extends StatelessWidget {
  final Listing l;
  const _ListingCard(this.l);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: l.imageUrl != null
              ? Image.network(l.imageUrl!, fit: BoxFit.cover)
              : Container(
                  color: cs.primaryContainer,
                  alignment: Alignment.center,
                  child: Text(l.name.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join().toUpperCase(),
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cs.onPrimaryContainer)),
                ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (l.rx || l.isService)
                Text(l.rx ? 'PRESCRIPTION' : 'SERVICE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: cs.secondary)),
              Text(l.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${l.providerName} · ${l.area}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const Spacer(),
              Row(children: [
                Expanded(child: Text(tsh(l.price), style: const TextStyle(fontWeight: FontWeight.w700))),
                IconButton.filled(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add),
                  tooltip: 'Add ${l.name}',
                  onPressed: () {
                    context.read<Cart>().add(l);
                    toast(context, 'Added to cart');
                  },
                ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ---------------- Cart + checkout ----------------
class _CartPage extends StatefulWidget {
  final AppUser user;
  final VoidCallback onPlaced;
  const _CartPage({required this.user, required this.onPlaced});

  @override
  State<_CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<_CartPage> {
  late final _addr = TextEditingController(text: '${widget.user.customer!['area']}, ');
  String _pay = 'mpesa';
  File? _rx;
  double? _lat, _lng;
  bool _busy = false;
  String? _error;

  Future<void> _useLocation() async {
    final p = await LocationService.current();
    if (!mounted) return;
    if (p == null) {
      toast(context, 'Allow location access to pin your exact spot.');
      return;
    }
    setState(() {
      _lat = p.latitude;
      _lng = p.longitude;
    });
    toast(context, 'Location pinned. The rider will see it on the map.');
  }

  Future<void> _pickRx() async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70);
    if (x != null) setState(() => _rx = File(x.path));
  }

  Future<void> _place(Cart cart) async {
    if (_addr.text.trim().length < 8) {
      setState(() => _error = 'Add a street or landmark so the rider can find you.');
      return;
    }
    if (cart.needsPrescription && _rx == null) {
      setState(() => _error = 'Take a photo of your prescription to order prescription medicine.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rxPath = _rx == null ? null : await Db.uploadPrescription(widget.user.uid, _rx!);
      final ids = await Db.createOrders(
        items: cart.toRequest(),
        address: _addr.text.trim(),
        lat: _lat,
        lng: _lng,
        payMethod: _pay,
        prescriptionPath: rxPath,
      );
      if (_pay != 'cash') {
        // Sends a payment prompt (USSD push) to the customer's phone for each order.
        for (final id in ids) {
          await Db.startMobilePayment(id, widget.user.phone);
        }
      }
      cart.clear();
      if (!mounted) return;
      toast(context, _pay == 'cash' ? 'Order placed' : 'Order placed. Approve the payment on your phone.');
      widget.onPlaced();
      Navigator.push(context, MaterialPageRoute(builder: (_) => TrackScreen(orderId: ids.first)));
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    if (cart.isEmpty) {
      return const EmptyState(icon: Icons.shopping_cart_outlined, title: 'Your cart is empty', body: 'Add items or book a service from Home.');
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final group in cart.byProvider.values)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(group.first.listing.providerName, style: const TextStyle(fontWeight: FontWeight.w700)),
              for (final line in group)
                Row(children: [
                  Expanded(child: Text('${line.listing.name}\n${tsh(line.listing.price)} / ${line.listing.unit}')),
                  IconButton(onPressed: () => cart.remove(line.listing), icon: const Icon(Icons.remove_circle_outline), tooltip: 'Fewer'),
                  Text('${line.qty}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  IconButton(onPressed: () => cart.add(line.listing), icon: const Icon(Icons.add_circle_outline), tooltip: 'More'),
                ]),
            ]),
          ),
        ),
      const SizedBox(height: 12),
      TextField(controller: _addr, decoration: const InputDecoration(labelText: 'Delivery address', hintText: 'Area, street, landmark')),
      TextButton.icon(
        onPressed: _useLocation,
        icon: Icon(_lat == null ? Icons.my_location : Icons.check_circle),
        label: Text(_lat == null ? 'Pin my exact location' : 'Location pinned'),
      ),
      if (cart.needsPrescription) ...[
        OutlinedButton.icon(
          onPressed: _pickRx,
          icon: Icon(_rx == null ? Icons.photo_camera_outlined : Icons.check_circle),
          label: Text(_rx == null ? 'Photograph your prescription' : 'Prescription added'),
        ),
        const Text('The pharmacy checks it before confirming your order.'),
      ],
      const SizedBox(height: 12),
      const Text('Pay with', style: TextStyle(fontWeight: FontWeight.w700)),
      for (final m in ['mpesa', 'airtel', 'cash'])
        RadioListTile(value: m, groupValue: _pay, title: Text(payLabel(m)), onChanged: (v) => setState(() => _pay = v!)),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            LineRow('Items', tsh(cart.subtotal)),
            LineRow('Delivery', tsh(cart.fees)),
            const Divider(),
            LineRow('Total', tsh(cart.total), bold: true),
          ]),
        ),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 12),
      FilledButton(onPressed: _busy ? null : () => _place(cart), child: Text(_busy ? 'Placing order…' : 'Place order · ${tsh(cart.total)}')),
    ]);
  }
}

// ---------------- Orders ----------------
class _Orders extends StatelessWidget {
  final String uid;
  const _Orders({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Order>>(
      stream: Db.customerOrders(uid),
      builder: (context, snap) {
        if (!snap.hasData) return const Loading();
        final list = snap.data!;
        if (list.isEmpty) {
          return const EmptyState(icon: Icons.inventory_2_outlined, title: 'No orders yet', body: 'Your orders and their live status show here.');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final o = list[i];
            return Card(
              child: ListTile(
                title: Text(o.providerName, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${o.code} · ${o.items.map((x) => '${x.qty} × ${x.name}').join(', ')}', maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: StatusChip(o),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrackScreen(orderId: o.id))),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------- Account ----------------
class _Account extends StatelessWidget {
  final AppUser user;
  const _Account({required this.user});

  @override
  Widget build(BuildContext context) {
    final c = user.customer!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text(c['name']), subtitle: Text(user.phone)),
      ListTile(title: const Text('Home area'), trailing: Text(c['area'] ?? '')),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => RegisterRoleScreen(uid: user.uid, phone: user.phone, role: Role.customer, existing: c),
        )),
        child: const Text('Edit details'),
      ),
      TextButton(onPressed: AuthService.signOut, child: const Text('Sign out')),
    ]);
  }
}
