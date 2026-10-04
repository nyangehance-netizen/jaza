import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'screens/gate.dart';
import 'services/push_service.dart';
import 'state/cart.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await PushService.init();
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
    );
  }
}
