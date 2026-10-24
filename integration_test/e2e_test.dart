// End-to-end test: the real app, on a real Android emulator/device, against
// the LOCAL Firebase Emulator Suite seeded with mock data. Never production —
// it refuses to start unless USE_FIREBASE_EMULATORS is set.
//
// Run it with integration_test/run_e2e_android.sh, which starts from fresh
// mock data, forwards the emulator ports, records the screen, and handles
// the steps that happen outside the app (pressing Home, tapping the push
// notification). See integration_test/README.md.
//
// Steps the host script must act on are announced with a line starting
// "E2E-STEP:" on stdout/logcat.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sabha_hq/core/firebase/emulators.dart';
import 'package:sabha_hq/main.dart' as app;

const orgId = String.fromEnvironment('E2E_ORG_ID');
const eventId = String.fromEnvironment('E2E_EVENT_ID');
const ownerEmail = String.fromEnvironment('E2E_OWNER_EMAIL');
const ownerPassword = String.fromEnvironment('E2E_OWNER_PASSWORD');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Render every frame in real time, so the screen recording shows the app
  // the way a person would see it rather than jumping between pumps.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'Movers/Pitchers, kiosk check-in and admin check-in notifications',
    (tester) async {
      expect(
        useFirebaseEmulators,
        isTrue,
        reason: 'Refusing to run against production Firebase.',
      );

      app.main();
      final ui = _Driver(tester);

      // ---------------------------------------------------------------
      // 1. Admin logs in on the phone.
      // ---------------------------------------------------------------
      await ui.step('Admin login');
      await ui.signIn();
      await ui.waitFor(find.text('Demo Day 2026'));
      await ui.pause();

      // QR code + check-in link for the kiosk (Share QR on mobile).
      await ui.tap(find.byIcon(Icons.qr_code));
      await ui.waitFor(find.text('Check-In: Demo Day 2026'));
      expect(find.text('Share QR'), findsOneWidget);
      expect(
        find.textContaining('https://sabha-hq.web.app/check-in?orgId=$orgId'),
        findsOneWidget,
        reason: 'mobile builds must link to the hosted web app',
      );
      await ui.pause(2500);
      await ui.tap(find.text('Close'));

      // ---------------------------------------------------------------
      // 2. Attendee directory: Mover / Pitcher name tags, add a Pitcher.
      // ---------------------------------------------------------------
      await ui.step('Attendee directory');
      await ui.tapNav('Attendees');
      await ui.waitFor(find.text('Attendee Directory'));
      // Sorted by name: Ananya (Mover) and Asha (Pitcher) are the top rows.
      await ui.waitFor(find.text('9876500002 • MOVER'));
      expect(find.text('9876500011 • PITCHER'), findsOneWidget);
      await ui.pause(2000);

      await ui.tap(find.widgetWithText(FloatingActionButton, 'Add Attendee'));
      await ui.waitFor(find.text('Add New Attendee'));
      await ui.type(find.widgetWithText(TextField, 'Full Name'), 'Dev Malhotra');
      await ui.type(
        find.widgetWithText(TextField, 'Email Address'),
        'dev@example.test',
      );
      await ui.type(find.widgetWithText(TextField, 'Phone Number'), '9876500021');
      await ui.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(DropdownButtonFormField<String>),
        ),
      );
      await ui.tap(find.text('Pitcher').last);
      await ui.pause(800);
      await ui.tap(find.widgetWithText(ElevatedButton, 'Add Attendee'));
      await ui.waitFor(find.text('9876500021 • PITCHER'));
      await ui.pause(2000);

      // ---------------------------------------------------------------
      // 3. Live feed, and the in-app banner for a check-in that happens
      //    while the admin is watching (door staff checking Karan in).
      // ---------------------------------------------------------------
      await ui.step('Live feed + foreground notification');
      await ui.tapNav('Live');
      await ui.waitFor(find.text('Movers (2)'));
      expect(find.text('Pitchers (2)'), findsOneWidget);
      await ui.pause(2000);

      await _staffCheckIn('9876500003'); // Karan Mehta, a Mover
      await ui.waitFor(find.text('Karan Mehta (Mover) just checked in!'));
      await ui.waitFor(find.text('Movers (3)'));
      await ui.pause(3000);

      // ---------------------------------------------------------------
      // 4. Analytics.
      // ---------------------------------------------------------------
      await ui.step('Analytics');
      await ui.tapNav('Analytics');
      await ui.waitFor(find.text('Total Registered'));
      expect(find.text('Movers'), findsOneWidget);
      expect(find.text('Pitchers'), findsOneWidget);
      expect(find.text('5\nChecked In'), findsOneWidget);
      await ui.pause(2500);

      // ---------------------------------------------------------------
      // 5. Push notification with the app in the background: the host
      //    script presses Home, a check-in happens, and the host taps the
      //    notification — which should open the live feed.
      // ---------------------------------------------------------------
      await ui.step('Background push notification');
      ui.hostAction('go-home');
      await ui.sleep(5000);
      await _staffCheckIn('9876500012'); // Vikram Shah, a Pitcher
      await ui.sleep(9000); // FCM delivery + heads-up banner on screen
      ui.hostAction('open-push');
      final openedFromPush = await ui.waitForResume(
        find.text('Live Check-In Feed'),
        timeout: const Duration(seconds: 20),
      );
      // Printed rather than asserted: delivery depends on the machine's
      // Firebase credentials reaching real FCM, not on this app's code —
      // the host script reports what it actually saw on screen.
      debugPrint('E2E-RESULT: push-opened-live-feed=$openedFromPush');
      if (!openedFromPush) await ui.tapNav('Live');
      await ui.waitFor(find.text('Pitchers (3)'));
      await ui.pause(2500);

      // ---------------------------------------------------------------
      // 6. Admin logs out (confirmation dialog on mobile).
      // ---------------------------------------------------------------
      await ui.step('Admin logout');
      await ui.tapNav('Logout');
      await ui.waitFor(find.text('Log out?'));
      await ui.pause(1000);
      await ui.tap(find.text('Log out'));
      await ui.waitFor(find.text('Forgot password?'));
      await ui.pause();

      // ---------------------------------------------------------------
      // 7. Kiosk: a pre-registered Mover checks in by phone.
      //    (On the web this is where the QR code lands.)
      // ---------------------------------------------------------------
      await ui.step('Kiosk check-in (pre-registered Mover)');
      ui.go('/check-in?orgId=$orgId&eventId=$eventId');
      await ui.waitFor(find.text('Enter Your Phone Number'));
      await ui.type(find.widgetWithText(TextField, 'Phone Number'), '9876500001');
      await ui.tap(find.text('Check In'));
      await ui.waitFor(find.text('Taking you to the live event...'));
      await ui.waitFor(find.text('Live Event'));
      await ui.waitFor(find.text('Mover Ravi Kumar', findRichText: true));
      // Newest first — Vikram (checked in by door staff in step 5) is right
      // below Ravi; earlier arrivals are further down the lazy list.
      expect(find.text('Pitcher Vikram Shah', findRichText: true), findsOneWidget);
      await ui.pause(3000);

      await ui.tap(find.byTooltip('Logout'));
      await ui.waitFor(find.text('Enter Your Phone Number'));

      // ---------------------------------------------------------------
      // 8. Kiosk: a walk-in registers (walk-ins become Pitchers), then
      //    leaves feedback.
      // ---------------------------------------------------------------
      await ui.step('Kiosk walk-in registration + feedback');
      await ui.type(find.widgetWithText(TextField, 'Phone Number'), '9876500099');
      await ui.tap(find.text('Check In'));
      await ui.waitFor(find.text('New Registration'));
      await ui.type(find.widgetWithText(TextField, 'Full Name *'), 'Priya Sharma');
      await ui.type(
        find.widgetWithText(TextField, 'Email Address *'),
        'priya@example.test',
      );
      await ui.type(find.widgetWithText(TextField, 'Company Name'), 'Orbit Labs');
      await ui.type(
        find.widgetWithText(TextField, 'Designation / Title'),
        'Co-founder',
      );
      await ui.type(find.widgetWithText(TextField, 'Industry'), 'SpaceTech');
      await ui.tap(find.text('Register & Check In'));
      await ui.waitFor(find.text('Live Event'));
      await ui.waitFor(find.text('Pitcher Priya Sharma', findRichText: true));
      await ui.pause(3000);

      await ui.tap(find.byTooltip('Give Feedback'));
      await ui.waitFor(find.text('Event Feedback'));
      await ui.tap(find.byIcon(Icons.star_border).at(4));
      await ui.type(
        find.widgetWithText(TextField, 'Comments (optional)'),
        'Great pitches, smooth check-in!',
      );
      await ui.tap(find.text('Submit Feedback'));
      await ui.waitFor(find.text('Thanks for your feedback!'));
      await ui.pause(2000);

      // ---------------------------------------------------------------
      // 9. Admin signs back in and sees everything that happened.
      // ---------------------------------------------------------------
      await ui.step('Admin sees kiosk activity');
      ui.go('/login');
      await ui.signIn();
      await ui.waitFor(find.text('Demo Day 2026'));
      await ui.tapNav('Live');
      await ui.waitFor(find.text('Movers (4)'));
      await ui.waitFor(find.text('Pitchers (4)'));
      expect(find.text('Mover Ravi Kumar', findRichText: true), findsOneWidget);
      expect(find.text('Pitcher Priya Sharma', findRichText: true), findsOneWidget);
      await ui.pause(3000);

      await ui.tapNav('Analytics');
      await ui.waitFor(find.text('Total Registered'));
      await ui.waitFor(find.textContaining('5.0 avg'));
      await ui.scrollDown();
      await ui.pause(3000);

      await ui.step('Done');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

/// What a door-staff member's device does — the same checkIn callable the
/// kiosk uses, called as the signed-in org member (any member may check
/// people in; see functions/src/checkIn.ts).
Future<void> _staffCheckIn(String phone) async {
  await FirebaseFunctions.instanceFor(region: 'asia-south1')
      .httpsCallable('checkIn')
      .call({'orgId': orgId, 'eventId': eventId, 'phone': phone});
}

/// Small helpers that keep the test readable and the recording watchable
/// (a short pause after each visible action).
class _Driver {
  _Driver(this.tester);
  final WidgetTester tester;

  Future<void> step(String name) async {
    debugPrint('E2E-STEP: --- $name ---');
    await pause(400);
  }

  /// Something only the host can do (outside the app) — the run script
  /// watches for these lines.
  void hostAction(String action) => debugPrint('E2E-STEP: $action');

  Future<void> sleep(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> pause([int ms = 1500]) async {
    await sleep(ms);
    await tester.pump();
  }

  Future<void> waitFor(
    Finder finder, {
    Duration timeout = const Duration(seconds: 40),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
      if (finder.evaluate().isNotEmpty) return;
      await sleep(200);
    }
    throw TestFailure('Timed out after $timeout waiting for $finder');
  }

  /// Like [waitFor], but safe while the app is backgrounded (no frames are
  /// produced then, so pumping would just stall). Returns whether [finder]
  /// showed up.
  Future<bool> waitForResume(Finder finder, {required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await sleep(500);
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        continue;
      }
      await tester.pump();
      if (finder.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  Future<void> tap(Finder finder) async {
    await waitFor(finder);
    await tester.ensureVisible(finder.first);
    await tester.pump();
    await tester.tap(finder.first);
    await pause(900);
  }

  Future<void> tapNav(String label) => tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );

  Future<void> type(Finder field, String text) async {
    await tap(field);
    await tester.enterText(field.first, text);
    await pause(500);
  }

  Future<void> signIn() async {
    await waitFor(find.text('Forgot password?'));
    await type(find.widgetWithText(TextFormField, 'Email'), ownerEmail);
    await type(find.widgetWithText(TextFormField, 'Password'), ownerPassword);
    await tap(find.text('Login'));
  }

  void go(String location) {
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  }

  Future<void> scrollDown() async {
    await tester.fling(find.byType(Scrollable).last, const Offset(0, -500), 1500);
    await pause(800);
  }
}
