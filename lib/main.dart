import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart'; // ADD THIS
import 'core/firebase/emulators.dart';
import 'firebase_options.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy(); // ADD THIS: Removes the '#' from web URLs

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Local Emulator Suite instead of production — debug/test builds only,
  // and only when explicitly asked for. See core/firebase/emulators.dart.
  if (useFirebaseEmulators) await connectToFirebaseEmulators();

  runApp(const ProviderScope(child: SabhaApp()));
}
