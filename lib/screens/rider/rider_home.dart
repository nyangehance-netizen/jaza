import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/auth_service.dart';
import '../../services/db.dart';
import '../../services/location_service.dart';
import '../../services/push_service.dart';
import '../../widgets/common.dart';
import '../auth/register_role.dart';

class RiderHome extends StatefulWidget {
  final AppUser user;
  final Widget switcher;
  const RiderHome({super.key, required this.user, required this.switcher});

  @override
  State<RiderHome> createState() => _RiderHomeState();
}

class _RiderHomeState extends State<RiderHome> {
  int _tab = 0;
  late final _jobs = Db.openJobs();
  late final _mine = Db.riderOrders(widget.user.uid);

  @override
  Widget build(BuildContext context) {
    final r = widget.user.rider!;
    final online = r['online'] == true;
    return Scaffold(
      appBar: AppBar(
        title: Text(r['name']),
        actions: [
          Row(children: [
            Text(online ? 'Online' : 'Offline'),
            Switch(
              value: online,
              onChanged: (v) async {
                await run(context, () => Db.setRiderOnline(widget.user.uid, v), done: v ? 'You will get new job alerts' : 'Job alerts paused');
                PushService.subscribeRiderJobs(v);
              },
            ),
          ]),
          widget.switcher,
        ],
      ),
      body: StreamBuilder<List<ShopOrder>>(
        stream: _mine,
        builder: (context, mineSnap) {
          final mine = mineSnap.data ?? [];
          return [
            _Jobs(stream: _jobs, user: widget.user, online: online, onTaken: () => setState(() => _tab = 1)),
            _Trips(trips: mine.where((o) => o.status == 'assigned' || o.status == 'onway').toList()),
            _Earnings(user: widget.user, done: mine.where((o) => o.status == 'delivered').toList()),
          ][_tab];
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.work_outline), label: 'Jobs'),
          NavigationDestination(icon: Icon(Icons.route_outlined), label: 'My trips'),
          NavigationDestination(icon: Icon(Icons.payments_outlined), label: 'Earnings'),
        ],
      ),
    );
  }
}

class _Jobs extends StatelessWidget {
  final Stream<List<ShopOrder>> stream;
  final AppUser user;
  final bool online;
  final VoidCallback onTaken;
  const _Jobs({required this.stream, required this.user, required this.online, required this.onTaken});

  @override
  Widget build(BuildContext context) {
    if (!online) {
      return const EmptyState(icon: Icons.power_settings_new, title: 'You are offline', body: 'Switch to Online at the top to see delivery jobs.');
    }
    return StreamBuilder<List<ShopOrder>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) return const Loading();
        final jobs = snap.data!;
        if (jobs.isEmpty) {
          return const EmptyState(icon: Icons.two_wheeler, title: 'No jobs right now', body: 'When a shop marks an order packed, it appears here and you get a notification.');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: jobs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final o = jobs[i];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text(o.providerName, style: const TextStyle(fontWeight: FontWeight.w700))),
                    Text('+${tsh(o.fee)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                  LineRow('Pickup', o.pickupArea),
                  LineRow('Drop-off', o.dropoffAddress),
                  Text(o.payMethod == 'cash' ? 'Collect ${tsh(o.total)} cash' : 'Already paid by ${payLabel(o.payMethod)}'),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () async {
                      try {
                        final ok = await Db.takeJob(o.id, user.uid, user.rider!, user.phone);
                        if (!context.mounted) return;
                        if (ok) {
                          toast(context, 'Job accepted. Head to the shop.');
                          onTaken();
                        } else {
                          toast(context, 'Another rider took this job first.');
                        }
                      } catch (e) {
                        if (context.mounted) toast(context, errorText(e));
                      }
                    },
                    child: const Text('Accept job'),
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

class _Trips extends StatelessWidget {
  final List<ShopOrder> trips;
  const _Trips({required this.trips});

  @override
  Widget build(BuildContext context) {
    if (trips.isEmpty) {
      return const EmptyState(icon: Icons.route_outlined, title: 'No active trips', body: 'Accept a job from the Jobs tab.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: trips.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _TripCard(trips[i]),
    );
  }
}

class _TripCard extends StatefulWidget {
  final ShopOrder o;
  const _TripCard(this.o);

  @override
  State<_TripCard> createState() => _TripCardState();
}

class _TripCardState extends State<_TripCard> {
  final _pin = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Resume sharing location if the app was closed mid-trip.
    if (widget.o.status == 'onway') LocationService.startSharing(widget.o.id);
  }

  Future<void> _start() async {
    final err = await LocationService.startSharing(widget.o.id);
    if (!mounted) return;
    if (err != null) {
      toast(context, err);
      return;
    }
    await run(context, () => Db.setStatus(widget.o.id, 'onway'), done: 'Trip started. The customer is tracking you.');
  }

  Future<void> _deliver() async {
    final ok = await run(context, () => Db.confirmDelivery(widget.o.id, _pin.text.trim()), done: 'Delivered. Asante!');
    if (ok) LocationService.stopSharing();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.o;
    final pickup = o.status == 'assigned';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('${o.customerName}  ·  ${o.code}', style: const TextStyle(fontWeight: FontWeight.w700))),
            StatusChip(o),
          ]),
          const SizedBox(height: 6),
          LineRow(pickup ? 'Pick up at' : 'Drop at', pickup ? '${o.providerName}, ${o.pickupArea}' : o.dropoffAddress),
          SelectableText(pickup ? 'Shop phone: ${o.providerPhone}' : 'Customer phone: ${o.customerPhone}'),
          if (o.payMethod == 'cash' && !pickup) Text('Collect ${tsh(o.total)} cash'),
          const SizedBox(height: 10),
          if (pickup)
            FilledButton.tonal(onPressed: _start, child: const Text('Picked up, start trip'))
          else
            Row(children: [
              Expanded(
                child: TextField(controller: _pin, keyboardType: TextInputType.number, maxLength: 4, decoration: const InputDecoration(labelText: 'Customer PIN', counterText: '')),
              ),
              const SizedBox(width: 8),
              FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(110, 56)), onPressed: _deliver, child: const Text('Delivered')),
            ]),
        ]),
      ),
    );
  }
}

class _Earnings extends StatelessWidget {
  final AppUser user;
  final List<ShopOrder> done;
  const _Earnings({required this.user, required this.done});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = user.rider!;
    Widget stat(String v, String label) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(v, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text(label),
              ]),
            ),
          ),
        );
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [stat('${done.length}', 'Deliveries'), stat(tsh(done.fold(0, (a, o) => a + o.fee)), 'Earned')]),
      for (final o in done)
        ListTile(title: Text('${o.providerName} → ${o.dropoffAddress.split(',').first}'), subtitle: Text(o.code), trailing: Text('+${tsh(o.fee)}')),
      const SizedBox(height: 12),
      ListTile(title: const Text('Vehicle'), trailing: Text('${r['vehicle']} ${r['plate'] ?? ''}')),
      OutlinedButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => RegisterRoleScreen(uid: user.uid, phone: user.phone, role: Role.rider, existing: r),
        )),
        child: const Text('Edit details'),
      ),
      TextButton(onPressed: AuthService.signOut, child: const Text('Sign out')),
    ]);
  }
}
