import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/models.dart';
import '../../services/auth_service.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';
import '../auth/register_role.dart';

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
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddListingScreen(user: widget.user))),
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
      case 'assigned':
        action = Text('${o.riderName ?? 'A rider'} is coming to pick up. ${o.riderPhone ?? ''}');
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
          return const EmptyState(icon: Icons.add_business_outlined, title: 'Nothing posted yet', body: 'Tap “Post listing” to add a product or service. Customers see it right away.');
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final l = list[i];
            return Card(
              child: ListTile(
                title: Text(l.name),
                subtitle: Text('${tsh(l.price)} / ${l.unit}${l.active ? '' : ' · Hidden'}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) => v == 'toggle'
                      ? run(context, () => Db.setListingActive(l.id, !l.active), done: l.active ? 'Hidden from customers' : 'Visible to customers')
                      : run(context, () => Db.deleteListing(l.id), done: 'Listing deleted'),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'toggle', child: Text(l.active ? 'Hide from customers' : 'Show to customers')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class AddListingScreen extends StatefulWidget {
  final AppUser user;
  const AddListingScreen({super.key, required this.user});

  @override
  State<AddListingScreen> createState() => _AddListingScreenState();
}

class _AddListingScreenState extends State<AddListingScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _price = TextEditingController(), _unit = TextEditingController(), _desc = TextEditingController();
  late String _cat = widget.user.provider!['cat'] ?? 'shopping';
  String _type = 'product';
  bool _rx = false, _busy = false;
  File? _image;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final p = widget.user.provider!;
    final ok = await run(context, () => Db.addListing({
          'providerId': widget.user.uid,
          'providerName': p['name'],
          'area': p['area'],
          'cat': _cat,
          'name': _name.text.trim(),
          'price': int.parse(_price.text.replaceAll(RegExp(r'\D'), '')),
          'unit': _unit.text.trim().isEmpty ? (_type == 'service' ? 'visit' : 'item') : _unit.text.trim(),
          'desc': _desc.text.trim(),
          'type': _type,
          'rx': _rx,
        }, image: _image), done: 'Posted. Customers can see it now.');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post a product or service')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          GestureDetector(
            onTap: () async {
              final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1200);
              if (x != null) setState(() => _image = File(x.path));
            },
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                clipBehavior: Clip.antiAlias,
                child: _image == null
                    ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add_a_photo_outlined, size: 36), SizedBox(height: 6), Text('Add a photo (optional)')]))
                    : Image.file(_image!, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Name'), validator: (v) => (v ?? '').trim().length < 3 ? 'Give it a name customers will recognise' : null),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'product', label: Text('Product'), icon: Icon(Icons.inventory_2_outlined)),
              ButtonSegment(value: 'service', label: Text('Service'), icon: Icon(Icons.handyman_outlined)),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField(
            value: _cat,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [for (final e in categories.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _cat = v!),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Price (TSh)'),
                validator: (v) => (int.tryParse((v ?? '').replaceAll(RegExp(r'\D'), '')) ?? 0) <= 0 ? 'Enter a price' : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: TextFormField(controller: _unit, decoration: const InputDecoration(labelText: 'Per', hintText: 'item, kg, visit'))),
          ]),
          const SizedBox(height: 14),
          TextFormField(controller: _desc, maxLines: 3, decoration: const InputDecoration(labelText: 'Description')),
          if (_cat == 'pharmacy')
            SwitchListTile(value: _rx, onChanged: (v) => setState(() => _rx = v), title: const Text('Needs a prescription')),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Posting…' : 'Post listing')),
        ]),
      ),
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
