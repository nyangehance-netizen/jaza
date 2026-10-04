import 'dart:math';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/demo_store.dart';

/// A simple drawn map for preview mode (no Google Maps key needed):
/// pickup, drop-off and the rider moving between them.
class PreviewMap extends StatelessWidget {
  final ShopOrder order;
  const PreviewMap({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final from = DemoStore.pointFor(order.pickupArea);
    final to = order.dropoff ?? DemoStore.pointFor('Mikocheni');
    final r = order.riderLoc ?? from;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: CustomPaint(
          painter: _MapPainter(
            from: Offset(from.longitude, from.latitude),
            to: Offset(to.longitude, to.latitude),
            rider: Offset(r.longitude, r.latitude),
            ground: cs.surfaceContainerHighest,
            road: cs.surface,
            route: cs.primary,
            dest: cs.secondary,
            text: cs.onSurface,
            fromLabel: order.pickupArea,
            toLabel: order.dropoffAddress.split(',').first,
          ),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  final Offset from, to, rider;
  final Color ground, road, route, dest, text;
  final String fromLabel, toLabel;
  _MapPainter({
    required this.from, required this.to, required this.rider, required this.ground, required this.road,
    required this.route, required this.dest, required this.text, required this.fromLabel, required this.toLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    final roadPaint = Paint()
      ..color = road
      ..strokeWidth = 10;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(Offset(0, size.height * i / 4), Offset(size.width, size.height * i / 4), roadPaint);
      canvas.drawLine(Offset(size.width * i / 4, 0), Offset(size.width * i / 4, size.height), roadPaint);
    }

    // Fit the trip into the box with a margin. North is up (latitude grows upward).
    final minX = min(from.dx, to.dx), maxX = max(from.dx, to.dx);
    final minY = min(from.dy, to.dy), maxY = max(from.dy, to.dy);
    final spanX = max(maxX - minX, 0.01), spanY = max(maxY - minY, 0.01);
    const pad = 36.0;
    Offset p(Offset g) => Offset(
          pad + (g.dx - minX) / spanX * (size.width - 2 * pad),
          size.height - pad - (g.dy - minY) / spanY * (size.height - 2 * pad),
        );

    final a = p(from), b = p(to), r = p(rider);
    final dash = Paint()
      ..color = route
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final total = (b - a).distance;
    for (double d = 0; d < total; d += 12) {
      final t1 = d / total, t2 = min((d + 5) / total, 1.0);
      canvas.drawLine(Offset.lerp(a, b, t1)!, Offset.lerp(a, b, t2)!, dash);
    }
    canvas.drawCircle(a, 8, Paint()..color = road);
    canvas.drawCircle(a, 8, Paint()
      ..color = route
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);
    canvas.drawCircle(b, 9, Paint()..color = dest);
    canvas.drawCircle(r, 16, Paint()..color = route.withValues(alpha: .2));
    canvas.drawCircle(r, 9, Paint()..color = route);
    canvas.drawCircle(r, 3.5, Paint()..color = road);

    void label(String s, Offset at) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(color: text, fontSize: 12, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width / 2);
      final x = (at.dx - tp.width / 2).clamp(4.0, size.width - tp.width - 4);
      final y = (at.dy + 14).clamp(4.0, size.height - tp.height - 4);
      tp.paint(canvas, Offset(x, y));
    }

    label(fromLabel, a);
    label(toLabel, b);
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.rider != rider || old.ground != ground;
}
