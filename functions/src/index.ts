import { onCall } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2";
import * as admin from "firebase-admin";

admin.initializeApp();

// Keep the whole app in one region — matches the Firestore database's
// location (asia-south1, see firebase.json) to avoid cross-region latency
// and egress cost on every call.
setGlobalOptions({ region: "asia-south1" });

/**
 * Phase 0 placeholder — proves the Functions deploy pipeline (build, auth,
 * region, emulator) works end to end before any real logic lands on top of
 * it. Safe to call from a signed-in client; does nothing but echo back.
 *
 * Superseded by real callables as the SaaS migration plan progresses:
 *   - Phase 1 / task 4: invite-accept -> sets {orgId, role} custom claims
 *   - Phase 1 / task 6: check-in moves here from direct client writes
 * See the "Sabha HQ SaaS migration plan" memory for the full plan.
 */
export const ping = onCall((request) => {
  return {
    ok: true,
    uid: request.auth?.uid ?? null,
    receivedAt: new Date().toISOString(),
  };
});

// Phase 1 / task 4: org membership via an invite-token flow.
// See functions/src/invites.ts for the full design and caveats.
export { createInvite, acceptInvite } from "./invites";

// Phase 1 / task 5: binds an anonymous guest session to one event so
// firestore.rules can scope it. See functions/src/guestSessions.ts.
export { beginGuestSession } from "./guestSessions";

// Phase 1 / task 6: check-in moves here, off the client. Clients no
// longer write to attendees directly (see firestore.rules and
// check_in_repository.dart). See functions/src/checkIn.ts.
export { checkIn, registerWalkIn } from "./checkIn";

// Phase 2 / task 7: self-serve org creation. See functions/src/orgs.ts.
export { createOrg } from "./orgs";

// Sabha HQ's own ops dashboard (platform-owner only, not customer-facing).
// See functions/src/platform.ts.
export {
  getPlatformOverview,
  getOrgDetail,
  updateOrgLimits,
  setOrgStatus,
  getPlatformAuditLog,
} from "./platform";

// Event creation moved here so maxEvents can actually be enforced — see
// functions/src/events.ts for why rules alone can't do this.
export { createEvent } from "./events";

// Push notification to every org owner/admin on every check-in. A
// Firestore trigger, not a callable — see functions/src/notifications.ts.
export { notifyAdminsOnCheckIn } from "./notifications";
