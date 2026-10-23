# Sabha HQ

A multi-tenant event check-in and live attendee-management platform. Organizations
("orgs") each run their own events — QR/link-based attendee check-in, a live
checked-in roster, an event agenda, post-event feedback, and analytics — all
under one Firestore project, isolated per org.

Sabha HQ is the product. **Unpuzzle is one customer using it, not the product
itself** — the app used to be branded around Unpuzzle specifically; that's
been corrected. Any `orgId`/org named "unpuzzle" you find in scripts or test
fixtures refers to that one customer's org, same as any other org would be.

## What's in the app

**Public / attendee-facing** (no login):
- `/check-in?orgId=…&eventId=…` — phone-number check-in, or a full walk-in
  registration form if the number isn't pre-registered. Reached via a QR code
  or link an admin generates from the Events screen.
- The **Live Event** screen right after check-in — a live roster of who
  else has checked in, the event's agenda ("what's happening now/next"), and
  a link to leave feedback.
- `/feedback?orgId=…&eventId=…` — a star rating + comment.

**Admin dashboard** (`/dashboard/*`, behind login):
- **Events** — create/edit events, set branding (color + logo shown on the
  public check-in screen), manage the agenda, generate the check-in QR code.
- **Attendees** — CSV import/export, manual add/edit, per-event attendee list.
- **Live** — a real-time feed of check-ins across one event or all of them.
- **Analytics** — check-in rate, Mover/Pitcher breakdown, feedback.
- **Team** — invite teammates (owner/admin/staff roles), see who's on the org.

**Attendee roles**: every attendee is a **Mover** or a **Pitcher** (walk-ins
register as Pitchers). These used to be called "guest" and "participant", and
that's still what's *stored* in Firestore (`role: 'guest' | 'participant'`) —
only the labels changed, so existing data and old CSVs keep working. See
`AttendeeRole` in `lib/core/models/attendee.dart`.

**Check-in notifications**: every owner/admin gets a push notification for
every check-in, on each device they've signed in on (Android, iOS, or the web
dashboard — the browser asks for permission on first load). While the
dashboard is open in the foreground an in-app banner shows instead. Sent by
the `notifyAdminsOnCheckIn` Firestore trigger in
`functions/src/notifications.ts`.

**Account**: `/login`, `/signup`, `/accept-invite?orgId=…&token=…`. A
signed-in admin with no org yet lands on an onboarding screen — create a new
org, or redeem an invite link.

## Architecture

- **Flutter** — web, Android and iOS from one codebase — with
  `flutter_riverpod` for state and `go_router` for routing. Web-only APIs
  (browser downloads) sit behind conditional imports
  (`lib/core/utils/file_saver.dart`); on mobile the same actions open the
  native share sheet. Links the mobile app generates (check-in QR codes,
  invites) point at the hosted web app (`lib/core/config/app_urls.dart`).
- **Firebase**: Firestore, Auth (email/password for admins, silent anonymous
  sessions for check-in guests), Cloud Functions (TypeScript), Hosting, and
  Cloud Messaging (check-in push notifications).
- **Multi-tenancy**: every org's data lives under `orgs/{orgId}/events/{eventId}/…`.
  Isolation is enforced by `firestore.rules`, keyed off custom claims
  (`{orgId, role}`) set server-side by Cloud Functions — never trust a client
  to say which org it belongs to. See [`docs/saas-schema.md`](docs/saas-schema.md)
  for the full schema and the reasoning behind it (in particular, why
  path-based isolation was chosen over a flat `orgId` field).
- **Server-side logic** (`functions/src/`): org creation, invites, binding an
  anonymous guest session to one event, and the check-in/walk-in writes
  themselves all run as Cloud Functions rather than direct client writes —
  see each file's header comment for why.

## Running it

```bash
flutter pub get
flutter run -d chrome
```

Cloud Functions live in `functions/` as a separate Node project:

```bash
cd functions
npm install
npm run build
```

### Tests

```bash
flutter test
```

Functions are tested against the Firebase emulators, not deployed
infrastructure — each suite spins up (and tears down) its own emulator
session via `firebase emulators:exec`:

```bash
cd functions
npm run test:migration   # bootstrap-org migration script
npm run test:invites     # invite-token flow + custom claims
npm run test:checkin     # check-in/walk-in callables
npm run test:orgs        # self-serve org creation
npm run test:notifications  # check-in push notifications: who gets them, what they say
npm run test:rules       # firestore.rules isolation guarantees (org A can't read org B, etc.)
```

## Deploying

Cloud Functions, Firestore rules/indexes, and the Flutter web build are
**separate deploy targets** — `firebase deploy --only functions`,
`--only firestore`, `--only hosting`. If you're migrating an existing
single-tenant deployment to the org-scoped schema, the order matters: deploy
Functions first, run the migration script for real, *then* deploy the new
rules and app build. `firestore.rules`'s own header comment spells this out.

### Push notification setup (one-time, per platform)

- **iOS**: upload an APNs authentication key in the Firebase console
  (Project settings → Cloud Messaging → Apple app configuration), and make sure
  the Apple Developer team that signs the app has the Push Notifications
  capability (`ios/Runner/Runner.entitlements` already requests it). Without
  the key, iOS devices register but never receive anything.
- **Android**: nothing extra — `google-services.json` is enough.
- **Web**: nothing extra — `web/firebase-messaging-sw.js` ships with the
  hosting build.
