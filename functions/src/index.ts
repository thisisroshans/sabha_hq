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
