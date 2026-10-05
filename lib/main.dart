import 'dart:io' show File, Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'models/models.dart';
import 'screens/gate.dart';
import 'services/app_mode.dart';
import 'services/auth_service.dart';
import 'services/demo_store.dart';
import 'services/push_service.dart';
import 'state/cart.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await PushService.init();
  } catch (_) {
    // No Firebase project connected yet: run with sample data on this phone.
    AppMode.preview = true;
    DemoStore.seed();
    // The build machine's screenshot check starts the app with LETEA_DEMO=track
    // to show a delivery in progress. Normal launches never set this.
    if (_demoRequested()) await _startTrackingDemo();
  }
  runApp(
    ChangeNotifierProvider(
      create: (_) => Cart(),
      child: const LeteaApp(),
    ),
  );
}

/// True when the build machine asked for the delivery demo, either with the
/// LETEA_DEMO=track setting or a `letea_demo` file in the app's tmp folder.
bool _demoRequested() {
  try {
    final env = Platform.environment;
    final home = env['HOME'];
    final asked = env['LETEA_DEMO'] == 'track' || (home != null && File('$home/tmp/letea_demo').existsSync());
    debugPrint('LETEA_DEMO check: env=${env['LETEA_DEMO']} home=$home asked=$asked');
    return asked;
  } catch (e) {
    debugPrint('LETEA_DEMO check failed: $e');
    return false;
  }
}

Future<void> _startTrackingDemo() async {
  const phone = '+255712000000';
  await AuthService.confirm(phone, AuthService.previewCode);
  final uid = DemoStore.currentUid!;
  DemoStore.users[uid] = AppUser(uid: uid, phone: phone, customer: {'name': 'Neema Mushi', 'area': 'Mikocheni'});
  final item = DemoStore.listings.firstWhere((l) => l.providerId == 'demo-p1');
  final ids = DemoStore.createOrders(uid, [{'listingId': item.id, 'qty': 2}], 'Mikocheni, near Shoppers Plaza', -6.7615, 39.2468, 'cash');
  AppMode.openOrderOnStart = ids.first;
}

class LeteaApp extends StatelessWidget {
  const LeteaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Letea',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const Gate(),
      builder: (context, child) => AppMode.preview
          ? Banner(message: 'PREVIEW', location: BannerLocation.topEnd, child: child!)
          : child!,
    );
  }
}
