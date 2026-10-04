import 'dart:io';

import 'package:flutter/material.dart';

/// Shows a product or service photo: an online photo, a photo saved on this
/// phone (preview mode), or, when there is none, a clean category tile.
class ListingPhoto extends StatelessWidget {
  final String? src;
  final String cat, name;
  final BoxFit fit;
  const ListingPhoto({super.key, required this.src, required this.cat, required this.name, this.fit = BoxFit.cover});

  static IconData iconFor(String cat) => switch (cat) {
        'pharmacy' => Icons.medication_outlined,
        'food' => Icons.restaurant_outlined,
        'services' => Icons.handyman_outlined,
        'parcel' => Icons.local_shipping_outlined,
        _ => Icons.shopping_basket_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final s = src;
    if (s == null || s.isEmpty) return _placeholder(context);
    if (s.startsWith('http')) {
      return Image.network(
        s,
        fit: fit,
        loadingBuilder: (c, child, p) => p == null ? child : _placeholder(c, loading: true),
        errorBuilder: (c, _, __) => _placeholder(c),
      );
    }
    return Image.file(File(s), fit: fit, errorBuilder: (c, _, __) => _placeholder(c));
  }

  Widget _placeholder(BuildContext context, {bool loading = false}) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = switch (cat) {
      'pharmacy' => (cs.tertiaryContainer, cs.onTertiaryContainer),
      'food' => (cs.secondaryContainer, cs.onSecondaryContainer),
      'services' => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
      _ => (cs.primaryContainer, cs.onPrimaryContainer),
    };
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [bg, Color.lerp(bg, fg, .12)!]),
      ),
      alignment: Alignment.center,
      child: loading
          ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
          : LayoutBuilder(
              builder: (_, c) => Icon(iconFor(cat), color: fg.withValues(alpha: .75), size: (c.maxHeight.isFinite ? c.maxHeight : 120) * .38),
            ),
    );
  }
}
