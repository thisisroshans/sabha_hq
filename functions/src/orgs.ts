import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { DEFAULT_LIMITS } from "./limits";

function db() {
  return admin.firestore();
}

interface CreateOrgData {
  orgName: string;
}

/**
 * Self-serve org creation (Phase 2, task #7) — the thing that was
 * previously only possible via functions/scripts/migrate-to-orgs.js run
 * by hand. Any signed-in Firebase Auth user (however they got an account
 * — email/password signup is the only path the Flutter app builds today)
 * can call this once to become the owner of a brand new org.
 *
 * "Once": this app assumes one org per admin account (see
 * lib/core/providers/current_org_provider.dart's doc comment) — someone
 * who already has an orgId claim is rejected rather than silently
 * getting a second org they'd have no UI to switch into. True multi-org
 * membership is a bigger feature this task doesn't build.
 *
 * plan defaults to 'free' — no billing exists yet (deliberately out of
 * scope for task #7, see docs/saas-schema.md), but the field is there
 * from day one so adding real plans later is additive, not a migration.
 */
export async function createOrgHandler(
  request: CallableRequest<CreateOrgData>
): Promise<{ orgId: string }> {
  const auth = request.auth;
  if (!auth) throw new HttpsError("unauthenticated", "Sign in first.");

  if (auth.token.orgId) {
    throw new HttpsError(
      "already-exists",
      "This account already belongs to an organization."
    );
  }

  const orgName = (request.data?.orgName ?? "").trim();
  if (!orgName) {
    throw new HttpsError("invalid-argument", "Organization name is required.");
  }

  const orgRef = db().collection("orgs").doc();
  const now = admin.firestore.FieldValue.serverTimestamp();

  await orgRef.set({
    name: orgName,
    plan: "free",
    status: "active",
    limits: DEFAULT_LIMITS,
    createdAt: now,
  });

  await orgRef.collection("members").doc(auth.uid).set({
    email: auth.token.email ?? null,
    role: "owner",
    joinedAt: now,
  });

  const existingClaims = (await admin.auth().getUser(auth.uid)).customClaims || {};
  await admin.auth().setCustomUserClaims(auth.uid, {
    ...existingClaims,
    orgId: orgRef.id,
    role: "owner",
  });

  return { orgId: orgRef.id };
}

export const createOrg = onCall(createOrgHandler);
