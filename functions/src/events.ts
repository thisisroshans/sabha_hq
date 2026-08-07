import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { orgLimits } from "./limits";

function db() {
  return admin.firestore();
}

/** Same {orgId, role} check every owner/admin-gated callable in this app
 * uses (invites.ts, checkIn.ts) — duplicated rather than shared because
 * each caller's error message differs slightly and the check is three
 * lines; not worth a shared helper yet. */
function isOwnerOrAdmin(auth: CallableRequest["auth"], orgId: string): boolean {
  if (!auth) return false;
  return auth.token.orgId === orgId && (auth.token.role === "owner" || auth.token.role === "admin");
}

interface CreateEventData {
  orgId: string;
  title: string;
  location: string;
  dateIso: string;
}

/**
 * Event creation moved here from a direct client write (EventRepository)
 * for exactly one reason: enforcing maxEvents. Firestore security rules
 * can check a single document's fields via get(), but can't run an
 * aggregate count() over a subcollection — there is no way to express
 * "reject this write if the org already has N events" in rules alone.
 * Reading/updating/deleting an existing event stays a direct client
 * write (see firestore.rules) since neither needs a quantity check.
 */
export async function createEventHandler(
  request: CallableRequest<CreateEventData>
): Promise<{ id: string }> {
  const data = request.data ?? ({} as CreateEventData);
  const orgId = data.orgId;
  const title = (data.title ?? "").trim();
  const location = (data.location ?? "").trim();

  if (typeof orgId !== "string" || !orgId) {
    throw new HttpsError("invalid-argument", "orgId is required.");
  }
  if (!isOwnerOrAdmin(request.auth, orgId)) {
    throw new HttpsError("permission-denied", "Only an owner or admin of this org can create events.");
  }
  if (!title) throw new HttpsError("invalid-argument", "Event title is required.");
  if (!location) throw new HttpsError("invalid-argument", "Event location is required.");

  const date = new Date(data.dateIso);
  if (Number.isNaN(date.getTime())) {
    throw new HttpsError("invalid-argument", "A valid event date is required.");
  }

  const orgRef = db().collection("orgs").doc(orgId);
  const orgSnap = await orgRef.get();
  if (!orgSnap.exists) throw new HttpsError("not-found", "Org not found.");
  if (orgSnap.data()?.status === "suspended") {
    throw new HttpsError("failed-precondition", "This organization is currently suspended.");
  }

  const eventCountSnap = await orgRef.collection("events").count().get();
  const limits = orgLimits(orgSnap.data());
  if (eventCountSnap.data().count >= limits.maxEvents) {
    throw new HttpsError(
      "resource-exhausted",
      `This organization has reached its event limit (${limits.maxEvents}). Contact Sabha HQ to raise it.`
    );
  }

  const eventRef = orgRef.collection("events").doc();
  await eventRef.set({
    title,
    location,
    date: admin.firestore.Timestamp.fromDate(date),
    // Matches Event.toJson()'s defaults (lib/core/models/event.dart) —
    // this callable produces the same document shape the old direct
    // client write did, so nothing downstream needs to change.
    branding: { primaryColor: "#673AB7", logoUrl: "" },
    totalRegistered: 0,
    totalCheckedIn: 0,
  });

  return { id: eventRef.id };
}

export const createEvent = onCall(createEventHandler);
