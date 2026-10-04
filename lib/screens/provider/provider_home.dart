import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/auth_service.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';
import '../../widgets/listing_photo.dart';
import 'listing_editor.dart';
import '../auth/register_role.dart';
import '../customer/track_screen.dart';

class ProviderHome extends StatefulWidget {
  final AppUser user;
  final Widget switcher;
  const ProviderHome({super.key, required this.user, required this.switcher});

  @override
  State<ProviderHome> createState() => _ProviderHomeState();
}

class _ProviderHomeState extends State<ProviderHome> {
  int _tab = 0;
  late final _orders = Db.providerOrders(widget.user.uid);

  @override
  Widget build(BuildContext context) {
    final p = widget.user.provider!;
    return Scaffold(
      appBar: AppBar(title: Text(p['name']), actions: [widget.switcher]),
      body: [_OrdersTab(stream: _orders), _ListingsTab(user: widget.user), _Business(user: widget.user)][_tab],
      floatingActionButton: _tab == 1
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ListingEditorScreen(user: widget.user))),
              icon: const Icon(Icons.add),
              label: const Text('Post listing'),
            )
          : null,
      bottomNavigationBar: StreamBuilder<List<ShopOrder>>(
        stream: _orders,
        builder: (context, snap) {
          final fresh = (snap.data ?? []).where((o) => o.status == 'placed').length;
          return NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              NavigationDestination(
                icon: Badge(isLabelVisible: fresh > 0, label: Text('$fresh'), child: const Icon(Icons.receipt_long_outlined)),
                label: 'Orders',
              ),
              const NavigationDestination(icon: Icon(Icons.storefront_outlined), label: 'My listings'),
              const NavigationDestination(icon: Icon(Icons.badge_outlined), label: 'Business'),
            ],
          );
        },
      ),
    );
  }
}

class _OrdersTab extends StatelessWidget {
  final Stream<List<ShopOrder>> stream;
  const _OrdersTab({required this.stream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ShopOrder>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) return const Loading();
        final list = snap.data!;
        if (list.isEmpty) {
          return const EmptyState(icon: Icons.receipt_long_outlined, title: 'No orders yet', body: 'Customers see your listings as soon as you post them. New orders appear here.');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _ProviderOrderCard(list[i]),
        );
      },
    );
  }
}

class _ProviderOrderCard extends StatefulWidget {
  final ShopOrder o;
  const _ProviderOrderCard(this.o);

  @override
  State<_ProviderOrderCard> createState() => _ProviderOrderCardState();
}

class _ProviderOrderCardState extends State<_ProviderOrderCard> {
  final _pin = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final o = widget.o;
    Widget? action;
    switch (o.status) {
      case 'placed':
        action = Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => run(context, () => Db.setStatus(o.id, 'cancelled'), done: 'Order declined'), child: const Text('Decline'))),
          const SizedBox(width: 8),
          Expanded(child: FilledButton(onPressed: () => run(context, () => Db.setStatus(o.id, 'accepted'), done: 'Order accepted'), child: const Text('Accept'))),
        ]);
      case 'accepted':
        action = FilledButton.tonal(
          onPressed: () => o.isService
              ? run(context, () => Db.setStatus(o.id, 'onway'), done: 'Customer can see you are on the way')
              : run(context, () => Db.setStatus(o.id, 'ready'), done: 'Riders nearby can see this job now'),
          child: Text(o.isService ? 'Start trip to customer' : 'Mark packed, call a rider'),
        );
      case 'ready':
        action = const Text('Waiting for a rider to accept…');
      case 'assigned' || 'onway' when !o.isService:
        action = OutlinedButton.icon(
          icon: const Icon(Icons.map_outlined),
          label: Text(o.status == 'assigned'
              ? 'Track ${o.riderName ?? 'rider'} coming to collect'
              : 'Track delivery to ${o.customerName}'),
          onPressed: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => TrackScreen(orderId: o.id, asCustomer: false),
          )),
        );
      case 'onway' when o.isService:
        action = Row(children: [
          Expanded(child: TextField(controller: _pin, keyboardType: TextInputType.number, maxLength: 4, decoration: const InputDecoration(labelText: 'Customer PIN', counterText: ''))),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 56)),
            onPressed: () => run(context, () => Db.confirmDelivery(o.id, _pin.text.trim()), done: 'Job completed'),
            child: const Text('Complete'),
          ),
        ]);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('${o.customerName}  ·  ${o.code}', style: const TextStyle(fontWeight: FontWeight.w700))),
            StatusChip(o),
          ]),
          const SizedBox(height: 6),
          OrderSummary(o),
          const SizedBox(height: 4),
          SelectableText('${o.isService ? 'Service at' : 'Deliver to'}: ${o.dropoffAddress} · ${o.customerPhone}'),
          if (o.payMethod != 'cash') Text('Payment: ${o.payStatus == 'paid' ? 'received' : 'not yet confirmed'}'),
          if (o.rxUrl != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.description_outlined),
                label: const Text('View prescription'),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(o.rxUrl!))),
                ),
              ),
            ),
          if (action != null) ...[const SizedBox(height: 10), action],
        ]),
      ),
    );
  }
}

class _ListingsTab extends StatelessWidget {
  final AppUser user;
  const _ListingsTab({required this.user});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Listing>>(
      stream: Db.myListings(user.uid),
      builder: (context, snap) {
        if (!snap.hasData) return const Loading();
        final list = snap.data!;
        if (list.isEmpty) {
          return const EmptyState(icon: Icons.add_business_outlined, title: 'Nothing posted yet', body: 'Tap “Post listing” to add a product or service with photos. Customers see it right away.');
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final l = list[i];
            void edit() => Navigator.push(context, MaterialPageRoute(builder: (_) => ListingEditorScreen(user: user, existing: l)));
            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: edit,
                child: Row(children: [
                  SizedBox(width: 92, height: 92, child: ListingPhoto(src: l.cover, cat: l.cat, name: l.name)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                      Text('${tsh(l.price)} / ${l.unit}'),
                      Text(
                        [if (!l.active) 'Hidden', l.photos.isEmpty ? 'No photos yet' : '${l.photos.length} photo${l.photos.length == 1 ? '' : 's'}'].join(' · '),
                        style: TextStyle(fontSize: 12, color: l.photos.isEmpty ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ]),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      switch (v) {
                        case 'edit':
                          edit();
                        case 'toggle':
                          run(context, () => Db.setListingActive(l.id, !l.active), done: l.active ? 'Hidden from customers' : 'Visible to customers');
                        default:
                          run(context, () => Db.deleteListing(l.id), done: 'Listing deleted');
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit details and photos')),
                      PopupMenuItem(value: 'toggle', child: Text(l.active ? 'Hide from customers' : 'Show to customers')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ]),
              ),
            );
          },
        );
      },
    );
  }
}

class _Business extends StatelessWidget {
  final AppUser user;
  const _Business({required this.user});

  @override
  Widget build(BuildContext context) {
    final p = user.provider!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      ListTile(leading: const CircleAvatar(child: Icon(Icons.storefront)), title: Text(p['name']), subtitle: Text(user.phone)),
      ListTile(title: const Text('Category'), trailing: Text(categories[p['cat']] ?? '')),
      ListTile(title: const Text('Location'), trailing: Text(p['area'] ?? '')),
      ListTile(
        title: const Text('Verification'),
        trailing: Text(p['verified'] == true ? 'Verified' : 'Pending review'),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => RegisterRoleScreen(uid: user.uid, phone: user.phone, role: Role.provider, existing: p),
        )),
        child: const Text('Edit details'),
      ),
      TextButton(onPressed: AuthService.signOut, child: const Text('Sign out')),
    ]);
  }
}
