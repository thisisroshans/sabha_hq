import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { normalizePhone, phoneLookupVariants } from "./phone";
import { orgLimits } from "./limits";

function db() {
  return admin.firestore();
}

/**
 * Same authorization the old client-side rules encoded (isOrgMember ||
 * isGuestSessionFor, see firestore.rules) — now enforced here instead,
 * since these callables are what write to attendees now, not the client
 * directly. Firestore rules for attendees/create+update were tightened
 * to owner/admin/staff only as part of this task; a guest's write path
 * is entirely through checkIn/registerWalkIn below.
 */
function callerIsAuthorized(
  auth: CallableRequest["auth"],
  orgId: string,
  eventId: string
): boolean {
  if (!auth) return false;
  const token = auth.token;

  if (token.firebase?.sign_in_provider === "anonymous") {
    // Bound to exactly this event by beginGuestSession (guestSessions.ts).
    return token.guestOrgId === orgId && token.guestEventId === eventId;
  }

  // Any org member — owner/admin/staff — can check attendees in.
  return token.orgId === orgId;
}

/** Fetches the org once per call and checks suspension — both checkIn
 * and registerWalkIn need the org doc anyway (for its limits), so this
 * combines "is this org even usable right now" with "here are its
 * limits" into one read instead of two separate lookups. */
async function requireActiveOrg(orgId: string): Promise<FirebaseFirestore.DocumentData> {
  const orgSnap = await db().collection("orgs").doc(orgId).get();
  if (!orgSnap.exists) throw new HttpsError("not-found", "Event not found.");
  const data = orgSnap.data()!;
  if (data.status === "suspended") {
    throw new HttpsError("failed-precondition", "This event is not currently available.");
  }
  return data;
}

const RATE_LIMIT_WINDOW_MS = 60_000;

/**
 * Lightweight per-(event, caller) cooldown — a rolling window of attempt
 * timestamps stored on one small doc, trimmed on each check. Not a
 * distributed rate limiter (no cross-region coordination, no protection
 * against someone burning through many anonymous accounts), but it's a
 * real deterrent against a single kiosk session hammering the search/
 * write path, implemented without adding infrastructure (Redis/
 * Memorystore) this app doesn't otherwise need.
 *
 * maxAttempts is per-org now (orgs/{orgId}.limits.checkInRateLimitPerMinute,
 * platform-owner adjustable) — it used to be a hardcoded constant here;
 * the default (8) is unchanged, so nothing shifts for an org until a
 * platform owner deliberately adjusts it.
 */
async function checkRateLimit(
  orgId: string,
  eventId: string,
  uid: string,
  maxAttempts: number
): Promise<void> {
  const ref = db()
    .collection("orgs")
    .doc(orgId)
    .collection("events")
    .doc(eventId)
    .collection("checkInRateLimits")
    .doc(uid);

  const now = Date.now();

  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const previousAttempts: number[] = (snap.data()?.attempts as number[]) ?? [];
    const recentAttempts = previousAttempts.filter((t) => now - t < RATE_LIMIT_WINDOW_MS);

    if (recentAttempts.length >= maxAttempts) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many attempts. Please wait a moment and try again."
      );
    }

    recentAttempts.push(now);
    tx.set(ref, { attempts: recentAttempts }, { merge: true });
  });
}

type LogResult =
  | "checked_in"
  | "already_checked_in"
  | "not_found"
  | "walk_in_registered";

/** Audit trail — who attempted what, when. Phone is stored normalized,
 * not raw, so partial/garbled input a guest mistyped isn't preserved. */
async function logAttempt(
  orgId: string,
  eventId: string,
  uid: string,
  phone: string,
  result: LogResult
): Promise<void> {
  await db()
    .collection("orgs")
    .doc(orgId)
    .collection("events")
    .doc(eventId)
    .collection("checkInLog")
    .add({
      uid,
      phone: normalizePhone(phone),
      result,
      at: admin.firestore.FieldValue.serverTimestamp(),
    });
}

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value;
}

// Firestore Timestamp doesn't survive a callable's JSON response as
// something the Dart client can parse without special-casing — serialize
// explicitly to ISO 8601 instead, same shape as what the OLD direct-write
// client code approximated with DateTime.now() after firing off a
// FieldValue.serverTimestamp() write.
function serializeAttendee(id: string, data: FirebaseFirestore.DocumentData) {
  const checkInTime = data.checkInTime as admin.firestore.Timestamp | undefined;
  return {
    ...data,
    id,
    checkInTime: checkInTime ? checkInTime.toDate().toISOString() : null,
  };
}

interface CheckInData {
  orgId: string;
  eventId: string;
  phone: string;
}

/** Search by phone; check the guest in if found and not already checked
 * in. Returns { found: false } (NOT an error) when there's no match, so
 * the client can fall through to the walk-in registration flow — same
 * contract the old direct-Firestore CheckInRepository.searchAndCheckIn
 * had, just server-side now. */
export async function checkInHandler(
  request: CallableRequest<CheckInData>
): Promise<{ found: boolean; attendee?: ReturnType<typeof serializeAttendee> }> {
  const { orgId, eventId, phone } = request.data ?? ({} as CheckInData);
  requireString(orgId, "orgId");
  requireString(eventId, "eventId");
  requireString(phone, "phone");

  if (!callerIsAuthorized(request.auth, orgId, eventId)) {
    throw new HttpsError("permission-denied", "Not authorized for this event.");
  }

  const org = await requireActiveOrg(orgId);
  const limits = orgLimits(org);
  await checkRateLimit(orgId, eventId, request.auth!.uid, limits.checkInRateLimitPerMinute);

  const variants = phoneLookupVariants(phone);
  if (variants.length === 0) {
    throw new HttpsError("invalid-argument", "Invalid phone number.");
  }

  const attendeesRef = db()
    .collection("orgs")
    .doc(orgId)
    .collection("events")
    .doc(eventId)
    .collection("attendees");

  // Same tolerant match as before (task #1's phone-format fix): a guest
  // imported as "+91 98765 43210" is still found typing the bare 10
  // digits at the kiosk.
  const querySnap = await attendeesRef.where("phone", "in", variants).limit(1).get();

  if (querySnap.empty) {
    await logAttempt(orgId, eventId, request.auth!.uid, phone, "not_found");
    return { found: false };
  }

  const doc = querySnap.docs[0];
  const data = doc.data();

  if (data.isCheckedIn) {
    await logAttempt(orgId, eventId, request.auth!.uid, phone, "already_checked_in");
    return { found: true, attendee: serializeAttendee(doc.id, data) };
  }

  const normalizedPhone = normalizePhone(phone);
  await doc.ref.update({
    isCheckedIn: true,
    checkInTime: admin.firestore.FieldValue.serverTimestamp(),
    // Self-heals legacy phone formats on check-in, same as before.
    phone: normalizedPhone,
  });

  await logAttempt(orgId, eventId, request.auth!.uid, phone, "checked_in");

  return {
    found: true,
    attendee: serializeAttendee(doc.id, {
      ...data,
      isCheckedIn: true,
      phone: normalizedPhone,
      checkInTime: admin.firestore.Timestamp.now(),
    }),
  };
}

interface RegisterWalkInData {
  orgId: string;
  eventId: string;
  phone: string;
  name: string;
  email: string;
  companyName?: string;
  designation?: string;
  industry?: string;
}

/** Registers a brand-new walk-in and checks them in immediately. */
export async function registerWalkInHandler(
  request: CallableRequest<RegisterWalkInData>
): Promise<ReturnType<typeof serializeAttendee>> {
  const data = request.data ?? ({} as RegisterWalkInData);
  const orgId = requireString(data.orgId, "orgId");
  const eventId = requireString(data.eventId, "eventId");
  const phone = requireString(data.phone, "phone");
  const name = requireString(data.name, "name");
  const email = requireString(data.email, "email");

  if (!callerIsAuthorized(request.auth, orgId, eventId)) {
    throw new HttpsError("permission-denied", "Not authorized for this event.");
  }

  const org = await requireActiveOrg(orgId);
  const limits = orgLimits(org);
  await checkRateLimit(orgId, eventId, request.auth!.uid, limits.checkInRateLimitPerMinute);

  const attendeesRef = db()
    .collection("orgs")
    .doc(orgId)
    .collection("events")
    .doc(eventId)
    .collection("attendees");

  // Enforced here (not via CSV import / manual add in the admin guest
  // list — those stay direct client writes and are a known, documented
  // gap, see docs/saas-schema.md) because this is the guest self-service
  // path most exposed to runaway growth: a kiosk left unattended
  // registering walk-ins has no other backstop.
  const attendeeCountSnap = await attendeesRef.count().get();
  if (attendeeCountSnap.data().count >= limits.maxAttendeesPerEvent) {
    throw new HttpsError(
      "resource-exhausted",
      `This event has reached its attendee limit (${limits.maxAttendeesPerEvent}).`
    );
  }

  const docRef = attendeesRef.doc();
  const normalizedPhone = normalizePhone(phone);

  const attendee = {
    eventId,
    orgId,
    name: name.trim(),
    email: email.trim(),
    phone: normalizedPhone,
    companyName: (data.companyName ?? "").trim(),
    designation: (data.designation ?? "").trim(),
    industry: (data.industry ?? "").trim(),
    role: "participant",
    isCheckedIn: true,
    checkInTime: admin.firestore.FieldValue.serverTimestamp(),
  };

  await docRef.set(attendee);
  await logAttempt(orgId, eventId, request.auth!.uid, phone, "walk_in_registered");

  return serializeAttendee(docRef.id, {
    ...attendee,
    checkInTime: admin.firestore.Timestamp.now(),
  });
}

export const checkIn = onCall(checkInHandler);
export const registerWalkIn = onCall(registerWalkInHandler);
