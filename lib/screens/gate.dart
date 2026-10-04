import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/db.dart';
import '../services/push_service.dart';
import '../widgets/common.dart';
import 'auth/phone_login.dart';
import 'auth/register_role.dart';
import 'customer/customer_home.dart';
import 'provider/provider_home.dart';
import 'rider/rider_home.dart';

/// Signed out → phone login. Signed in → the home for the chosen role.
class Gate extends StatelessWidget {
  const Gate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Session?>(
      stream: AuthService.changes,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Scaffold(body: Loading());
        final u = snap.data;
        if (u == null) return const PhoneLoginScreen();
        return RoleShell(key: ValueKey(u.uid), uid: u.uid, phone: u.phone);
      },
    );
  }
}

class RoleShell extends StatefulWidget {
  final String uid, phone;
  const RoleShell({super.key, required this.uid, required this.phone});

  @override
  State<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends State<RoleShell> {
  Role? _role;
  late final Stream<AppUser?> _user = Db.user(widget.uid);

  @override
  void initState() {
    super.initState();
    PushService.registerDevice(widget.uid);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: _user,
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Loading());
        }
        final user = snap.data;
        final roles = user?.roles ?? [];
        if (roles.isEmpty) {
          return RolePicker(onPick: (r) => _openRegister(r));
        }
        final role = (_role != null && roles.contains(_role)) ? _role! : roles.first;
        final switcher = RoleSwitcher(
          current: role,
          roles: roles,
          onSwitch: (r) => setState(() => _role = r),
          onAdd: (r) => _openRegister(r),
        );
        return switch (role) {
          Role.customer => CustomerHome(user: user!, switcher: switcher),
          Role.provider => ProviderHome(user: user!, switcher: switcher),
          Role.rider => RiderHome(user: user!, switcher: switcher),
        };
      },
    );
  }

  Future<void> _openRegister(Role r) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => RegisterRoleScreen(uid: widget.uid, phone: widget.phone, role: r),
    ));
    if (ok == true) setState(() => _role = r);
  }
}

/// First screen after login: what will you use Letea for?
class RolePicker extends StatelessWidget {
  final void Function(Role) onPick;
  const RolePicker({super.key, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget option(Role r, IconData icon, String body) => Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Icon(icon, size: 32),
            title: Text(roleLabel(r), style: t.titleMedium),
            subtitle: Text(body),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onPick(r),
          ),
        );
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const SizedBox(height: 24),
          Text('Karibu Letea', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('How will you use Letea? You can add the other roles later.'),
          const SizedBox(height: 20),
          option(Role.customer, Icons.shopping_bag_outlined, 'Order shopping, medicine, food and home services.'),
          option(Role.provider, Icons.storefront_outlined, 'Sell products or offer services to customers near you.'),
          option(Role.rider, Icons.two_wheeler, 'Deliver orders on your boda, bajaji or car and earn per trip.'),
          const SizedBox(height: 12),
          TextButton(onPressed: AuthService.signOut, child: const Text('Sign out')),
        ]),
      ),
    );
  }
}

/// App-bar menu to switch role, add a role or sign out.
class RoleSwitcher extends StatelessWidget {
  final Role current;
  final List<Role> roles;
  final void Function(Role) onSwitch, onAdd;
  const RoleSwitcher({super.key, required this.current, required this.roles, required this.onSwitch, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Switch role',
      icon: const Icon(Icons.swap_horiz),
      onSelected: (v) {
        if (v == 'signout') {
          AuthService.signOut();
        } else if (v.startsWith('add:')) {
          onAdd(Role.values.byName(v.substring(4)));
        } else {
          onSwitch(Role.values.byName(v));
        }
      },
      itemBuilder: (_) => [
        for (final r in roles)
          CheckedPopupMenuItem(value: r.name, checked: r == current, child: Text('Use as ${roleLabel(r)}')),
        const PopupMenuDivider(),
        for (final r in Role.values.where((r) => !roles.contains(r)))
          PopupMenuItem(value: 'add:${r.name}', child: Text('Register as ${roleLabel(r)}')),
        const PopupMenuItem(value: 'signout', child: Text('Sign out')),
      ],
    );
  }
}
