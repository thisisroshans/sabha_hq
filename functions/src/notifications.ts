import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

function db() {
  return admin.firestore();
}

/** Where tapping a notification on web lands. Mirrors hostedAppOrigin in
 * lib/core/config/app_urls.dart — keep the two in step if the app moves
 * to a custom domain. */
const PUBLIC_APP_URL = "https://sabha-hq.web.app";

/** Who gets a push for every check-in. Staff devices register too (see
 * lib/core/notifications/check_in_notifications.dart) but aren't sent
 * to — deciding by role HERE, at send time, rather than at registration
 * means a promotion or demotion takes effect on the very next check-in. */
const NOTIFIED_ROLES = ["owner", "admin"];

/** Must match the channel MainActivity.kt creates on Android. */
const ANDROID_CHANNEL_ID = "check_ins";

/** FCM's "this token will never work again" errors — the app was
 * uninstalled, the browser revoked permission, or the device logged out
 * (check_in_notifications.dart deletes its token on logout). The device
 * doc is deleted so the next check-in doesn't retry it. Anything else
 * (quota, transient server errors) leaves the doc alone. */
const DEAD_TOKEN_ERRORS = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

/** Same rename as AttendeeRole in lib/core/models/attendee.dart — guests
 * are "Movers" and participants "Pitchers" now, but only as display
 * labels: the stored role values ('guest'/'participant') are unchanged. */
export function roleLabel(role: unknown): string {
  return typeof role === "string" && role.trim().toLowerCase() === "participant" ? "Pitcher" : "Mover";
}

/** True exactly once per attendee per check-in: on the write that flips
 * isCheckedIn to true (checkIn callable, or an admin marking someone in)
 * or that creates a doc already checked in (registerWalkIn). False for a
 * "welcome back" re-scan of someone already in, for the phone
 * self-heal update, for CSV imports (always isCheckedIn: false), and for
 * deletes. */
export function isNewCheckIn(
  before: FirebaseFirestore.DocumentData | undefined,
  after: FirebaseFirestore.DocumentData | undefined
): boolean {
  return after?.isCheckedIn === true && before?.isCheckedIn !== true;
}

export interface NotifyResult {
  sent: number;
  failed: number;
  removedDevices: number;
}

type Sender = Pick<admin.messaging.Messaging, "sendEachForMulticast">;

/**
 * Pushes one check-in to every device registered by an owner/admin of the
 * org (orgs/{orgId}/members/{uid}/devices/{token}, written by the app —
 * see firestore.rules). Exported separately from the trigger, with an
 * injectable sender, so scripts/_smoke-test-notifications.js can run it
 * against the Firestore emulator without a real FCM project.
 */
export async function notifyAdminsOfCheckIn(
  orgId: string,
  eventId: string,
  attendeeId: string,
  attendee: FirebaseFirestore.DocumentData,
  sender: Sender = admin.messaging()
): Promise<NotifyResult> {
  const result: NotifyResult = { sent: 0, failed: 0, removedDevices: 0 };

  const orgRef = db().collection("orgs").doc(orgId);
  const membersSnap = await orgRef.collection("members").where("role", "in", NOTIFIED_ROLES).get();
  if (membersSnap.empty) return result;

  const deviceSnaps = await Promise.all(membersSnap.docs.map((member) => member.ref.collection("devices").get()));

  // Keyed by token: one browser or phone can end up registered under two
  // accounts in the same org (two admins taking turns on a shared
  // laptop) — it should still get each check-in once, not twice.
  const refsByToken = new Map<string, FirebaseFirestore.DocumentReference[]>();
  for (const snap of deviceSnaps) {
    for (const device of snap.docs) {
      refsByToken.set(device.id, [...(refsByToken.get(device.id) ?? []), device.ref]);
    }
  }
  const tokens = [...refsByToken.keys()];
  if (tokens.length === 0) return result;

  const eventSnap = await orgRef.collection("events").doc(eventId).get();
  const eventTitle = (eventSnap.get("title") as string | undefined) || "your event";

  const name = (typeof attendee.name === "string" && attendee.name.trim()) || "Someone";
  const company = typeof attendee.companyName === "string" ? attendee.companyName.trim() : "";
  const title = `${name} checked in`;
  // e.g. "Pitcher · Demo Day 2026 · Acme"
  const body = [roleLabel(attendee.role), eventTitle, company].filter(Boolean).join(" · ");

  const deadRefs: FirebaseFirestore.DocumentReference[] = [];

  // sendEachForMulticast takes at most 500 tokens per call.
  for (let i = 0; i < tokens.length; i += 500) {
    const batch = tokens.slice(i, i + 500);
    const response = await sender.sendEachForMulticast({
      tokens: batch,
      notification: { title, body },
      // What the app reads when the notification is tapped
      // (check_in_notifications.dart's startTapHandling). FCM data values
      // must all be strings.
      data: { type: "check_in", orgId, eventId, attendeeId },
      android: {
        priority: "high",
        notification: { channelId: ANDROID_CHANNEL_ID },
      },
      apns: { payload: { aps: { sound: "default" } } },
      webpush: { fcmOptions: { link: `${PUBLIC_APP_URL}/dashboard/live` } },
    });

    result.sent += response.successCount;
    result.failed += response.failureCount;
    response.responses.forEach((r, index) => {
      if (!r.success && r.error && DEAD_TOKEN_ERRORS.has(r.error.code)) {
        deadRefs.push(...(refsByToken.get(batch[index]) ?? []));
      }
    });
  }

  await Promise.all(deadRefs.map((ref) => ref.delete()));
  result.removedDevices = deadRefs.length;
  return result;
}

/**
 * "Admin receives a notification for every check-in." A Firestore trigger
 * rather than a call added to checkIn/registerWalkIn (functions/src/
 * checkIn.ts) because those aren't the only way someone gets checked in —
 * an org member can also flip isCheckedIn directly (firestore.rules
 * allows attendee updates for any member). Watching the document itself
 * catches every path, including ones added later, and keeps a slow or
 * failing FCM send from ever delaying or failing the kiosk's check-in.
 *
 * Firestore triggers are delivered at-least-once, so a rare duplicate
 * notification is possible; a missed one isn't.
 */
export const notifyAdminsOnCheckIn = onDocumentWritten(
  "orgs/{orgId}/events/{eventId}/attendees/{attendeeId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after || !isNewCheckIn(before, after)) return;

    const { orgId, eventId, attendeeId } = event.params;
    const result = await notifyAdminsOfCheckIn(orgId, eventId, attendeeId, after);
    logger.info("Check-in notification sent", { orgId, eventId, attendeeId, ...result });
  }
);
