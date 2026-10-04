import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/models.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';
import '../../widgets/listing_photo.dart';

/// Post a new product or service, or edit one, with up to [maxPhotos] photos.
class ListingEditorScreen extends StatefulWidget {
  final AppUser user;
  final Listing? existing;
  const ListingEditorScreen({super.key, required this.user, this.existing});

  @override
  State<ListingEditorScreen> createState() => _ListingEditorScreenState();
}

/// A photo in the editor: one already saved (url/path) or a new file.
class _Photo {
  final String? saved;
  final File? file;
  _Photo.saved(this.saved) : file = null;
  _Photo.file(this.file) : saved = null;
}

class _ListingEditorScreenState extends State<ListingEditorScreen> {
  static const maxPhotos = 5;
  final _form = GlobalKey<FormState>();
  late final Listing? e = widget.existing;
  late final _name = TextEditingController(text: e?.name);
  late final _price = TextEditingController(text: e == null ? '' : '${e!.price}');
  late final _unit = TextEditingController(text: e?.unit);
  late final _desc = TextEditingController(text: e?.desc);
  late String _cat = e?.cat ?? widget.user.provider!['cat'] ?? 'shopping';
  late String _type = e?.type ?? 'product';
  late bool _rx = e?.rx ?? false;
  late final List<_Photo> _photos = [for (final p in e?.photos ?? const <String>[]) _Photo.saved(p)];
  bool _busy = false;

  Future<void> _add(ImageSource source) async {
    final room = maxPhotos - _photos.length;
    if (room <= 0) return;
    final picker = ImagePicker();
    final files = source == ImageSource.camera
        ? [if (await picker.pickImage(source: source, imageQuality: 75, maxWidth: 1400) case final x?) x]
        : room == 1 // the gallery's multi-pick needs a limit of at least 2
            ? [if (await picker.pickImage(source: source, imageQuality: 75, maxWidth: 1400) case final x?) x]
            : await picker.pickMultiImage(imageQuality: 75, maxWidth: 1400, limit: room);
    if (files.isEmpty) return;
    setState(() => _photos.addAll(files.take(room).map((x) => _Photo.file(File(x.path)))));
  }

  void _photoMenu(int i) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (i > 0)
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('Make this the cover photo'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _photos.insert(0, _photos.removeAt(i)));
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Remove photo'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _photos.removeAt(i));
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final p = widget.user.provider!;
    final ok = await run(
      context,
      () => Db.saveListing(
        {
          'providerId': widget.user.uid,
          'providerName': p['name'],
          'area': p['area'],
          'cat': _cat,
          'name': _name.text.trim(),
          'price': int.parse(_price.text.replaceAll(RegExp(r'\D'), '')),
          'unit': _unit.text.trim().isEmpty ? (_type == 'service' ? 'visit' : 'item') : _unit.text.trim(),
          'desc': _desc.text.trim(),
          'type': _type,
          'rx': _cat == 'pharmacy' && _rx,
        },
        existingId: e?.id,
        keep: [for (final x in _photos) if (x.saved != null) x.saved!],
        newPhotos: [for (final x in _photos) if (x.file != null) x.file!],
      ),
      done: e == null ? 'Posted. Customers can see it now.' : 'Changes saved',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  Widget _thumb(int i) {
    final x = _photos[i];
    final img = x.file != null ? Image.file(x.file!, fit: BoxFit.cover) : ListingPhoto(src: x.saved, cat: _cat, name: _name.text);
    return GestureDetector(
      onTap: () => _photoMenu(i),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(fit: StackFit.expand, children: [
          img,
          if (i == 0)
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                child: const Text('Cover', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(e == null ? 'Post a product or service' : 'Edit listing')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Photos (${_photos.length}/$maxPhotos)', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            _type == 'service'
                ? 'Show your work: before and after, your tools, your team. Clear photos get more bookings.'
                : 'Use clear photos on a plain background. The first photo is the cover customers see.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length + (_photos.length < maxPhotos ? 2 : 0),
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                if (i < _photos.length) return SizedBox(width: 104, child: _thumb(i));
                final camera = i == _photos.length;
                return SizedBox(
                  width: 104,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: () => _add(camera ? ImageSource.camera : ImageSource.gallery),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(camera ? Icons.photo_camera_outlined : Icons.photo_library_outlined),
                      const SizedBox(height: 4),
                      Text(camera ? 'Take photo' : 'From gallery', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
                );
              },
            ),
          ),
          if (_photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Tap a photo to make it the cover or remove it.', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
          const SizedBox(height: 18),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (v) => (v ?? '').trim().length < 3 ? 'Give it a name customers will recognise' : null,
          ),
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
            items: [for (final c in categories.entries) DropdownMenuItem(value: c.key, child: Text(c.value))],
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
          TextFormField(controller: _desc, maxLines: 4, decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true)),
          if (_cat == 'pharmacy')
            SwitchListTile(value: _rx, onChanged: (v) => setState(() => _rx = v), title: const Text('Needs a prescription')),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? (_photos.any((x) => x.file != null) ? 'Uploading photos…' : 'Saving…') : (e == null ? 'Post listing' : 'Save changes')),
          ),
        ]),
      ),
    );
  }
}
