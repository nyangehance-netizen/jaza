import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'screens/gate.dart';
import 'services/app_mode.dart';
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
  }
  runApp(
    ChangeNotifierProvider(
      create: (_) => Cart(),
      child: const LeteaApp(),
    ),
  );
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
