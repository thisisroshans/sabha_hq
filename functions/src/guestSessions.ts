import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

function db() {
  return admin.firestore();
}

interface BeginGuestSessionData {
  orgId: string;
  eventId: string;
}

/**
 * Binds an anonymous guest's Firebase Auth session to exactly one event,
 * via custom claims {guestOrgId, guestEventId}. Firestore rules cannot
 * otherwise tell "an anonymous session that checked into event X" apart
 * from "an anonymous session that checked into event Y" — both are just
 * sign_in_provider == 'anonymous' — so without this, an org-scoped rule
 * for guests would have to be scoped to "any event in the org" at best,
 * or "any event anywhere" at worst (today's actual bug).
 *
 * NOT the same job as task #6 (move check-in to a callable function) —
 * this only stamps a claim so rules can check it; the actual
 * search/check-in/walk-in writes still go through CheckInRepository
 * directly for now. Task #6 is the bigger lift of moving that logic
 * server-side too.
 *
 * The Flutter side calling this is task #9 (app cutover) — right after
 * GuestAuthController.ensureSignedIn() succeeds, before any Firestore
 * read/write, the check-in screen needs to call this with the eventId
 * from its query parameter. Not wired up yet.
 */
export async function beginGuestSessionHandler(
  request: CallableRequest<BeginGuestSessionData>
): Promise<{ ok: true }> {
  const auth = request.auth;
  if (!auth) throw new HttpsError("unauthenticated", "Sign in first.");
  if (auth.token.firebase?.sign_in_provider !== "anonymous") {
    throw new HttpsError(
      "failed-precondition",
      "This is only for anonymous guest check-in sessions."
    );
  }

  const { orgId, eventId } = request.data ?? ({} as BeginGuestSessionData);
  if (typeof orgId !== "string" || !orgId) {
    throw new HttpsError("invalid-argument", "orgId is required.");
  }
  if (typeof eventId !== "string" || !eventId) {
    throw new HttpsError("invalid-argument", "eventId is required.");
  }

  // Don't mint a claim binding this session to an event that doesn't
  // exist under this org — cheap check, closes an easy garbage-in path.
  const eventSnap = await db().collection("orgs").doc(orgId).collection("events").doc(eventId).get();
  if (!eventSnap.exists) {
    throw new HttpsError("not-found", "Event not found.");
  }

  const existingClaims = (await admin.auth().getUser(auth.uid)).customClaims || {};
  await admin.auth().setCustomUserClaims(auth.uid, {
    ...existingClaims,
    guestOrgId: orgId,
    guestEventId: eventId,
  });

  return { ok: true };
}

export const beginGuestSession = onCall(beginGuestSessionHandler);
