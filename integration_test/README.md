# End-to-end test (Android, recorded)

`e2e_test.dart` drives the real app on an Android emulator or device against
the **local Firebase Emulator Suite** seeded with mock data. It never touches
production: the app only switches to the emulators when built with
`USE_FIREBASE_EMULATORS=true` (see `lib/core/firebase/emulators.dart`), and the
test refuses to start without it.

What it covers, in order:

1. Admin logs in → event list → check-in QR code (links to the hosted web app).
2. Attendee directory shows **Mover / Pitcher** name tags; adds a Pitcher.
3. Live feed's Movers / Pitchers columns; a check-in while the admin watches
   pops the in-app banner.
4. Analytics: Movers / Pitchers counts.
5. App in the background → a check-in → **push notification** → tapping it
   opens the live feed.
6. Admin logs out (confirmation dialog).
7. Kiosk: a pre-registered Mover checks in by phone.
8. Kiosk: a walk-in registers (becomes a Pitcher) and leaves feedback.
9. Admin logs back in and sees all of it in the live feed and analytics.

## Running it

```bash
npm --prefix functions run build
firebase emulators:start --only auth,firestore,functions --project sabha-hq
```

Then, in another terminal, with an emulator running (`flutter emulators --launch <id>`):

```bash
integration_test/run_e2e_android.sh emulator-5554
```

The script reseeds the emulators (`functions/scripts/seed-e2e-emulator.js`),
forwards the emulator ports to the device with `adb reverse`, runs the test,
presses Home / taps the push notification when the test asks it to, and
writes the screen recording to `build/e2e/sabha_hq_e2e.mp4` (needs `ffmpeg` on
`PATH` to stitch the 170-second `screenrecord` segments together).

Mock data and the throwaway emulator login live in `e2e_fixture.json`, which
both the seed script and the test (`--dart-define-from-file`) read.

**Push notifications (step 5)** are the one thing the emulators can't fake:
Cloud Messaging has no emulator, so the Functions emulator sends through the
real FCM service using the Firebase CLI's login on this machine — only ever to
the test device's own token. Without that login, every other step still
passes and the test prints `push-opened-live-feed=false`.
