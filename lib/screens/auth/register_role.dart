import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/db.dart';
import '../../services/push_service.dart';
import '../../widgets/common.dart';
import '../../widgets/pick_location.dart';
import '../../services/map_config.dart';
import 'package:latlong2/latlong.dart';

/// Register (or edit) the customer, provider or rider profile for this account.
class RegisterRoleScreen extends StatefulWidget {
  final String uid, phone;
  final Role role;
  final Map<String, dynamic>? existing;
  const RegisterRoleScreen({super.key, required this.uid, required this.phone, required this.role, this.existing});

  @override
  State<RegisterRoleScreen> createState() => _RegisterRoleScreenState();
}

class _RegisterRoleScreenState extends State<RegisterRoleScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?['name']);
  late final _plate = TextEditingController(text: widget.existing?['plate']);
  late String _area = widget.existing?['area'] ?? areas.first;
  late String _cat = widget.existing?['cat'] ?? 'shopping';
  late String _vehicle = widget.existing?['vehicle'] ?? 'Boda';
  late double? _lat = (widget.existing?['lat'] as num?)?.toDouble();
  late double? _lng = (widget.existing?['lng'] as num?)?.toDouble();

  Future<void> _pickShop() async {
    final start = _lat != null ? LatLng(_lat!, _lng!) : MapConfig.areaPoint(_area);
    final p = await Navigator.push<LatLng>(context, MaterialPageRoute(
      builder: (_) => PickLocationScreen(title: 'Where is your shop?', initial: start),
    ));
    if (p != null) {
      setState(() {
        _lat = p.latitude;
        _lng = p.longitude;
      });
    }
  }
  bool _busy = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final data = <String, dynamic>{'name': _name.text.trim()};
    switch (widget.role) {
      case Role.customer:
        data['area'] = _area;
      case Role.provider:
        data.addAll({'cat': _cat, 'area': _area, 'verified': widget.existing?['verified'] ?? false});
        if (_lat != null) data.addAll({'lat': _lat, 'lng': _lng});
      case Role.rider:
        data.addAll({'vehicle': _vehicle, 'plate': _plate.text.trim().toUpperCase(), 'online': widget.existing?['online'] ?? false});
    }
    final ok = await run(context, () => Db.saveRole(widget.uid, widget.phone, widget.role, data),
        done: widget.existing == null ? 'Account created' : 'Saved');
    if (widget.role == Role.rider && widget.existing == null) PushService.subscribeRiderJobs(true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.role;
    final title = widget.existing != null
        ? 'Edit details'
        : switch (r) {
            Role.customer => 'Set up your account',
            Role.provider => 'Register your business',
            Role.rider => 'Register as a rider',
          };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          TextFormField(
            controller: _name,
            decoration: InputDecoration(labelText: r == Role.provider ? 'Business name' : 'Full name'),
            validator: (v) => (v ?? '').trim().length < 2 ? 'Enter a name' : null,
          ),
          const SizedBox(height: 14),
          if (r == Role.provider) ...[
            DropdownButtonFormField(
              value: _cat,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [for (final e in categories.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _cat = v!),
            ),
            const SizedBox(height: 14),
          ],
          if (r != Role.rider)
            DropdownButtonFormField(
              value: _area,
              decoration: InputDecoration(labelText: r == Role.provider ? 'Location' : 'Home area'),
              items: [for (final a in areas) DropdownMenuItem(value: a, child: Text(a))],
              onChanged: (v) => setState(() => _area = v!),
            ),
          if (r == Role.provider) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _pickShop,
              icon: Icon(_lat == null ? Icons.add_location_alt_outlined : Icons.check_circle),
              label: Text(_lat == null ? 'Pin your shop on the map' : 'Shop pinned on the map (change)'),
            ),
            const Text('Riders use this pin to find you. Customers see it on their tracking map.'),
          ],
          if (r == Role.rider) ...[
            DropdownButtonFormField(
              value: _vehicle,
              decoration: const InputDecoration(labelText: 'Vehicle'),
              items: [for (final v in ['Boda', 'Bajaji', 'Bicycle', 'Car']) DropdownMenuItem(value: v, child: Text(v))],
              onChanged: (v) => setState(() => _vehicle = v!),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _plate,
              decoration: const InputDecoration(labelText: 'Plate number', hintText: 'MC 123 ABC'),
              validator: (v) => _vehicle != 'Bicycle' && (v ?? '').trim().length < 5 ? 'Enter your plate number' : null,
            ),
          ],
          if (r == Role.provider && widget.existing == null) ...[
            const SizedBox(height: 14),
            const Text('Pharmacies are checked by the Letea team before prescription medicine goes live.'),
          ],
          const SizedBox(height: 24),
          FilledButton(onPressed: _busy ? null : _save, child: Text(widget.existing == null ? 'Create account' : 'Save changes')),
        ]),
      ),
    );
  }
}
