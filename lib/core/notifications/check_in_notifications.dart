import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

/// The device side of check-in push notifications — the sending side is
/// functions/src/notifications.ts's notifyAdminsOnCheckIn.
///
/// Every signed-in org member's device registers its FCM token at
/// orgs/{orgId}/members/{uid}/devices/{token}; that function pushes to
/// the devices of every owner/admin in the org whenever one of its
/// attendees is checked in. Staff devices register too but aren't sent
/// to — the role check happens server-side at send time, so promoting a
/// staff member to admin takes effect on their very next check-in
/// without them having to sign out and back in.
///
/// While the app is in the foreground, the OS doesn't display these
/// (Android and web never do for a notification message; iOS doesn't
/// unless asked to, and isn't) — AdminScaffold's in-app snackbar covers
/// the foreground case instead, so an admin watching the dashboard isn't
/// told about the same check-in twice.
class CheckInNotifications {
  CheckInNotifications._();
  static final instance = CheckInNotifications._();

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  ({String orgId, String uid})? _registeredFor;
  String? _registeredToken;
  StreamSubscription<String>? _tokenRefreshSub;
  bool _registering = false;
  bool _tapHandlingStarted = false;

  // FCM has no Windows/macOS/Linux support, and the app doesn't run there
  // anyway (firebase_options.dart throws) — guard rather than assume.
  bool get _isSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  String get _platformName {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  }

  DocumentReference<Map<String, dynamic>> _deviceDoc(
    String orgId,
    String uid,
    String token,
  ) => FirebaseFirestore.instance
      .collection('orgs')
      .doc(orgId)
      .collection('members')
      .doc(uid)
      .collection('devices')
      .doc(token);

  Future<void> _saveToken(String orgId, String uid, String token) {
    // Shape must match firestore.rules' devices match block exactly.
    return _deviceDoc(orgId, uid, token).set({
      'platform': _platformName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Asks for notification permission (first time only — the OS remembers
  /// the answer) and registers this device for [uid] in [orgId]. Safe to
  /// call on every dashboard load: it's a no-op once registered for the
  /// same account. Never throws — a denied permission, a browser without
  /// push support, or an iOS simulator just means no pushes, not a broken
  /// dashboard.
  Future<void> register({required String orgId, required String uid}) async {
    if (!_isSupported) return;
    if (_registeredFor == (orgId: orgId, uid: uid)) return;
    // The org id can resolve more than once in quick succession on
    // dashboard load; one permission prompt / token write is enough.
    if (_registering) return;
    _registering = true;

    try {
      final settings = await _messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied ||
          settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        return;
      }

      // iOS hands the app its APNs token asynchronously, sometimes a beat
      // after permission is granted on first launch, and getToken() throws
      // until it has one. Give it a few seconds before giving up; the next
      // dashboard load will try again.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        for (var attempt = 0; attempt < 5; attempt++) {
          if (await _messaging.getAPNSToken() != null) break;
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (await _messaging.getAPNSToken() == null) return;
      }

      final token = await _messaging.getToken();
      if (token == null) return;

      await _saveToken(orgId, uid, token);
      _registeredFor = (orgId: orgId, uid: uid);
      _registeredToken = token;

      _tokenRefreshSub ??= _messaging.onTokenRefresh.listen(_onTokenRefresh);
    } catch (e) {
      debugPrint('Check-in notifications unavailable on this device: $e');
    } finally {
      _registering = false;
    }
  }

  Future<void> _onTokenRefresh(String newToken) async {
    final registration = _registeredFor;
    if (registration == null) return;
    final oldToken = _registeredToken;
    try {
      await _saveToken(registration.orgId, registration.uid, newToken);
      _registeredToken = newToken;
      if (oldToken != null && oldToken != newToken) {
        await _deviceDoc(
          registration.orgId,
          registration.uid,
          oldToken,
        ).delete();
      }
    } catch (e) {
      debugPrint('Could not update check-in notification token: $e');
    }
  }

  /// Stops pushes to this device. Must run BEFORE signing out —
  /// firestore.rules only lets a member delete their own devices while
  /// still signed in as themselves.
  Future<void> unregister() async {
    final registration = _registeredFor;
    final token = _registeredToken;
    _registeredFor = null;
    _registeredToken = null;
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;

    if (registration == null || token == null) return;

    try {
      await _deviceDoc(registration.orgId, registration.uid, token).delete();
    } catch (e) {
      debugPrint('Could not remove check-in notification device: $e');
    }

    // Also invalidate the token itself at FCM. If the delete above failed
    // (offline, say), the stale device doc would otherwise keep sending
    // this org's check-ins to whoever signs in on this device next — and
    // they may belong to a different org entirely. A dead token makes the
    // function's next send fail as unregistered, and it cleans the doc up
    // itself then.
    try {
      await _messaging.deleteToken();
    } catch (e) {
      debugPrint('Could not delete FCM token: $e');
    }
  }

  /// Tapping a check-in notification opens the live check-in feed. On web
  /// the service worker handles the click instead (web/firebase-messaging-sw.js
  /// opens the link the function attaches).
  void startTapHandling(GoRouter router) {
    if (!_isSupported || kIsWeb || _tapHandlingStarted) return;
    _tapHandlingStarted = true;

    void open(RemoteMessage message) {
      if (message.data['type'] != 'check_in') return;
      router.go('/dashboard/live');
    }

    // Tapped while the app was in the background...
    FirebaseMessaging.onMessageOpenedApp.listen(open);
    // ...or launched the app from terminated.
    _messaging
        .getInitialMessage()
        .then((message) {
          if (message != null) open(message);
        })
        .catchError((Object e) {
          debugPrint('Could not read launch notification: $e');
        });
  }
}
