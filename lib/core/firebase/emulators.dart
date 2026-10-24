import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Opt-in only: `--dart-define=USE_FIREBASE_EMULATORS=true`. Every normal
/// build (and every deploy) leaves this false and talks to production.
/// The end-to-end test (integration_test/e2e_test.dart) refuses to run
/// without it, so it can never seed or check in mock attendees against
/// real data.
const useFirebaseEmulators = bool.fromEnvironment('USE_FIREBASE_EMULATORS');

/// Points Auth, Firestore and Cloud Functions at the local Emulator Suite
/// (ports from firebase.json). Must run right after Firebase.initializeApp,
/// before anything touches Firestore.
///
/// 'localhost' everywhere, with FlutterFire's automatic Android rewrite to
/// 10.0.2.2 turned off: on an Android emulator or a USB device the ports
/// are forwarded with `adb reverse` instead (see integration_test/README.md),
/// which works the same on both and keeps the traffic on loopback.
Future<void> connectToFirebaseEmulators() async {
  const host = 'localhost';
  await FirebaseAuth.instance.useAuthEmulator(
    host,
    9099,
    automaticHostMapping: false,
  );
  FirebaseFirestore.instance.useFirestoreEmulator(
    host,
    8080,
    automaticHostMapping: false,
  );
  // Same region every callable call site uses — FirebaseFunctions caches
  // one instance per region, so redirecting it here redirects them all.
  FirebaseFunctions.instanceFor(region: 'asia-south1').useFunctionsEmulator(
    host,
    5001,
    automaticHostMapping: false,
  );
}
