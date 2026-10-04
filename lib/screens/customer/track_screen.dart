import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../services/db.dart';
import '../../widgets/delivery_map.dart';
import '../../widgets/common.dart';

/// Live order tracking: status timeline, rider on the map, delivery PIN.
class TrackScreen extends StatefulWidget {
  final String orderId;

  /// The customer sees the delivery PIN; the shop opening the same screen does not.
  final bool asCustomer;
  const TrackScreen({super.key, required this.orderId, this.asCustomer = true});

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  late final _stream = Db.order(widget.orderId);
  late final _pin = widget.asCustomer ? Db.deliveryPin(widget.orderId) : Future<String?>.value(null);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ShopOrder>(
      stream: _stream,
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: Loading());
        final o = snap.data!;
        return Scaffold(
          appBar: AppBar(title: Text(o.code)),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(child: Text(o.providerName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
              StatusChip(o),
            ]),
            const SizedBox(height: 12),
            if (o.status == 'cancelled')
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(o.payStatus == 'paid'
                      ? 'The provider declined this order. Your ${payLabel(o.payMethod)} payment will be refunded.'
                      : 'The provider declined this order. Nothing was charged.'),
                ),
              ),
            if (!o.isService && o.isOpen && o.status != 'cancelled')
              Padding(padding: const EdgeInsets.only(bottom: 12), child: DeliveryMap(order: o, height: 300)),
            if (widget.asCustomer && o.isOpen && o.status != 'cancelled') _pinCard(o),
            if (o.riderName != null)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.two_wheeler)),
                  title: Text(o.riderName!),
                  subtitle: SelectableText('${o.riderPlate ?? ''} · ${o.riderPhone ?? ''}'),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Progress', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ..._timeline(context, o),
                ]),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  OrderSummary(o),
                  const SizedBox(height: 6),
                  Text('To: ${o.dropoffAddress}'),
                  if (o.payMethod != 'cash') Text('Payment: ${o.payStatus == 'paid' ? 'received' : 'waiting for approval on your phone'}'),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _pinCard(ShopOrder o) => FutureBuilder<String?>(
        future: _pin,
        builder: (context, snap) => Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(
                child: Text(o.isService
                    ? 'Give this PIN to the provider when the job is done.'
                    : 'Give this PIN to the rider when you receive your order. Don\'t share it before.'),
              ),
              const SizedBox(width: 12),
              Text(snap.data ?? '····',
                  style: TextStyle(fontSize: 28, letterSpacing: 6, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
            ]),
          ),
        ),
      );

  List<Widget> _timeline(BuildContext context, ShopOrder o) {
    final steps = stepsFor(o);
    final idx = steps.indexWhere((s) => s.$1 == o.status);
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat.Hm();
    return [
      for (var i = 0; i < steps.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(
              (o.status == 'delivered' || i < idx) ? Icons.check_circle : (i == idx ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              color: i <= idx || o.status == 'delivered' ? cs.primary : cs.outline,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(steps[i].$2)),
            if (o.times[steps[i].$1] != null) Text(fmt.format(o.times[steps[i].$1]!.toDate()), style: TextStyle(color: cs.onSurfaceVariant)),
          ]),
        ),
    ];
  }
}
