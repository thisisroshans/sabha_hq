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
 * NOT the same job as checkIn.ts's checkIn/registerWalkIn — this only
 * stamps a claim so rules (and those callables) can check it; the actual
 * search/check-in/walk-in writes happen there, server-side, not here.
 *
 * Called from GuestAuthController.ensureGuestSession(), right after
 * ensureSignedIn() succeeds and before any Firestore read/write — see
 * lib/features/attendee_check_in/application/phone_auth_controller.dart.
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
  const [orgSnap, eventSnap] = await Promise.all([
    db().collection("orgs").doc(orgId).get(),
    db().collection("orgs").doc(orgId).collection("events").doc(eventId).get(),
  ]);
  if (!eventSnap.exists) {
    throw new HttpsError("not-found", "Event not found.");
  }
  // Fail here rather than letting the guest fill out the phone form only
  // to have checkIn/registerWalkIn reject it a step later — both of those
  // check suspension too (defense in depth, not reliance on this alone).
  if (orgSnap.data()?.status === "suspended") {
    throw new HttpsError("failed-precondition", "This event is not currently available.");
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
