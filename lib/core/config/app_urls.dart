import 'package:flutter/foundation.dart' show kIsWeb;

/// Where the web app is publicly hosted (Firebase Hosting, see
/// firebase.json). Mirrored by PUBLIC_APP_URL in
/// functions/src/notifications.ts — keep the two in step if this moves to
/// a custom domain.
const hostedAppOrigin = 'https://sabha-hq.web.app';

/// Origin that shareable links (check-in QR codes, team invites) are built
/// against.
///
/// On web this is wherever the dashboard is being served from, so links
/// made on a local dev server or a preview channel point back at that same
/// build. The native Android/iOS apps have no meaningful origin of their
/// own (Uri.base is a file:/// path there), and the people opening these
/// links — attendees scanning a QR code, invitees on a laptop — won't have
/// the app installed anyway, so native builds always link to the hosted
/// web app.
String get publicAppOrigin => kIsWeb ? Uri.base.origin : hostedAppOrigin;
