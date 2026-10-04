import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/cart.dart';
import '../../widgets/common.dart';
import '../../widgets/listing_photo.dart';

/// Product or service page: swipe through photos, read the details, add to cart.
class ListingDetailScreen extends StatefulWidget {
  final Listing listing;
  const ListingDetailScreen({super.key, required this.listing});

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  int _page = 0;

  void _openFull(int start) {
    final photos = widget.listing.photos;
    Navigator.push(context, MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: PageView.builder(
          controller: PageController(initialPage: start),
          itemCount: photos.length,
          itemBuilder: (_, i) => InteractiveViewer(
            maxScale: 4,
            child: Center(child: ListingPhoto(src: photos[i], cat: widget.listing.cat, name: widget.listing.name, fit: BoxFit.contain)),
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.listing;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final cart = context.watch<Cart>();
    final inCart = cart.lines.where((x) => x.listing.id == l.id).fold(0, (a, x) => a + x.qty);
    final photos = l.photos;

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 320,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(fit: StackFit.expand, children: [
              if (photos.isEmpty)
                ListingPhoto(src: null, cat: l.cat, name: l.name)
              else
                PageView.builder(
                  itemCount: photos.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => _openFull(i),
                    child: ListingPhoto(src: photos[i], cat: l.cat, name: l.name),
                  ),
                ),
              if (photos.length > 1)
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 0; i < photos.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _page ? 18 : 7,
                        height: 7,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: i == _page ? 1 : .6), borderRadius: BorderRadius.circular(4)),
                      ),
                  ]),
                ),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          sliver: SliverList.list(children: [
            if (l.rx || l.isService)
              Text(l.rx ? 'PRESCRIPTION NEEDED' : 'HOME SERVICE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cs.secondary, letterSpacing: .5)),
            Text(l.name, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('${tsh(l.price)} / ${l.unit}', style: t.titleLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Icon(ListingPhoto.iconFor(l.cat))),
              title: Text(l.providerName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${categories[l.cat] ?? ''} · ${l.area}'),
            ),
            if (l.desc.isNotEmpty) ...[
              const Divider(),
              const SizedBox(height: 8),
              Text(l.desc, style: t.bodyLarge),
            ],
            if (l.rx) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('You will be asked for a photo of your prescription at checkout. The pharmacy checks it before confirming.', style: TextStyle(color: cs.onSurfaceVariant)),
                ),
              ),
            ],
          ]),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: inCart == 0
              ? FilledButton.icon(
                  onPressed: () {
                    context.read<Cart>().add(l);
                    toast(context, l.isService ? 'Added. Book it from your cart.' : 'Added to cart');
                  },
                  icon: const Icon(Icons.add_shopping_cart),
                  label: Text(l.isService ? 'Book this service' : 'Add to cart'),
                )
              : Row(children: [
                  IconButton.outlined(onPressed: () => context.read<Cart>().remove(l), icon: const Icon(Icons.remove), tooltip: 'Fewer'),
                  Expanded(child: Text('$inCart in cart', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                  IconButton.filled(onPressed: () => context.read<Cart>().add(l), icon: const Icon(Icons.add), tooltip: 'More'),
                ]),
        ),
      ),
    );
  }
}
