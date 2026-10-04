import 'dart:ui' show FontFeature;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
}

/// Readable message for any error from Firebase or our functions.
String errorText(Object e) {
  if (e is FirebaseFunctionsException) return e.message ?? 'Something went wrong. Try again.';
  final s = e.toString();
  if (s.contains('permission-denied')) return "You can't do that on this order any more. Pull down to refresh.";
  if (s.contains('unavailable') || s.contains('network')) return 'No connection. Check your internet and try again.';
  return 'Something went wrong. Try again.';
}

/// Runs an action, shows a spinner-free success or error message.
Future<bool> run(BuildContext context, Future<void> Function() action, {String? done}) async {
  try {
    await action();
    if (context.mounted && done != null) toast(context, done);
    return true;
  } catch (e) {
    if (context.mounted) toast(context, errorText(e));
    return false;
  }
}

class StatusChip extends StatelessWidget {
  final Order order;
  const StatusChip(this.order, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = switch (order.status) {
      'placed' => (cs.secondaryContainer, cs.onSecondaryContainer),
      'cancelled' => (cs.errorContainer, cs.onErrorContainer),
      'delivered' => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
      _ => (cs.primaryContainer, cs.onPrimaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(statusLabel(order), style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, body;
  const EmptyState({super.key, required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class LineRow extends StatelessWidget {
  final String left, right;
  final bool bold;
  const LineRow(this.left, this.right, {super.key, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final st = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(left, style: st)),
        Text(right, style: st.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
}

/// Order lines + totals, shared by customer, provider and rider screens.
class OrderSummary extends StatelessWidget {
  final Order order;
  const OrderSummary(this.order, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final i in order.items) LineRow('${i.qty} × ${i.name}', tsh(i.price * i.qty)),
      if (order.fee > 0) LineRow('Delivery', tsh(order.fee)),
      const Divider(),
      LineRow('Total · ${payLabel(order.payMethod)}', tsh(order.total), bold: true),
    ]);
  }
}

String payLabel(String m) => switch (m) {
      'mpesa' => 'M-Pesa',
      'airtel' => 'Airtel Money',
      _ => 'Cash on delivery',
    };
