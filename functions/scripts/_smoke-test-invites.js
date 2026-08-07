#!/usr/bin/env node
/**
 * Throwaway smoke test for createInviteHandler/acceptInviteHandler
 * (functions/src/invites.ts) — NOT part of the deployed Functions
 * codebase. Run only via `npm run test:invites`, which uses
 * `firebase emulators:exec` against the Firestore+Auth emulators.
 *
 * Calls the exported *handler* functions directly with a hand-built
 * CallableRequest, rather than going through onCall()/the Functions
 * emulator/a client SDK — those layers are Google's code, not worth
 * re-testing; this exercises the actual business logic in invites.ts.
 *
 * Covers: happy path (create -> accept -> claims + membership set),
 * unauthorized create (caller isn't owner/admin of the org), wrong-email
 * accept (invite bound to a different address), and re-accepting an
 * already-used invite.
 */

const assert = require("assert");
const admin = require("firebase-admin");
const { createInviteHandler, acceptInviteHandler } = require("../lib/invites");

function fakeRequest(auth, data) {
  return { auth, data };
}

async function expectHttpsError(promise, code) {
  try {
    await promise;
  } catch (err) {
    assert.strictEqual(err.code, code, `expected HttpsError code '${code}', got '${err.code}': ${err.message}`);
    return err;
  }
  throw new Error(`expected an HttpsError('${code}') to be thrown, but nothing was`);
}

async function main() {
  if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw new Error("Refusing to run outside the emulator — set via `firebase emulators:exec`.");
  }

  admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "sabha-hq" });
  const db = admin.firestore();
  const auth = admin.auth();

  const orgId = "unpuzzle";
  await db.collection("orgs").doc(orgId).set({ name: "Unpuzzle", createdAt: admin.firestore.FieldValue.serverTimestamp() });

  const owner = await auth.createUser({ email: "owner@example.com", password: "smoke-test-123" });
  const staff = await auth.createUser({ email: "staff@example.com", password: "smoke-test-123" });
  const outsider = await auth.createUser({ email: "outsider@example.com", password: "smoke-test-123" });
  const invitee = await auth.createUser({ email: "invitee@example.com", password: "smoke-test-123" });
  const wrongPerson = await auth.createUser({ email: "wrong-person@example.com", password: "smoke-test-123" });

  console.log("--- Unauthorized create is rejected ---");
  await expectHttpsError(
    createInviteHandler(
      fakeRequest({ uid: outsider.uid, token: { email: "outsider@example.com" } }, { orgId, email: "invitee@example.com", role: "staff" })
    ),
    "permission-denied"
  );
  console.log("OK: non-member cannot create an invite.\n");

  console.log("--- Happy path: owner invites, invitee accepts ---");
  const { token, expiresAt } = await createInviteHandler(
    fakeRequest({ uid: owner.uid, token: { email: "owner@example.com", orgId, role: "owner" } }, { orgId, email: "invitee@example.com", role: "staff" })
  );
  assert.ok(token && token.length > 20, "expected a real token to come back");
  assert.ok(new Date(expiresAt).getTime() > Date.now(), "expiry should be in the future");
  console.log(`OK: invite created, token=${token.slice(0, 8)}...`);

  console.log("--- Wrong email cannot accept someone else's invite ---");
  await expectHttpsError(
    acceptInviteHandler(fakeRequest({ uid: wrongPerson.uid, token: { email: "wrong-person@example.com" } }, { orgId, token })),
    "permission-denied"
  );
  console.log("OK: mismatched email rejected.\n");

  const result = await acceptInviteHandler(fakeRequest({ uid: invitee.uid, token: { email: "invitee@example.com" } }, { orgId, token }));
  assert.deepStrictEqual(result, { orgId, role: "staff" });
  console.log("OK: invitee accepted.");

  const inviteeUser = await auth.getUser(invitee.uid);
  assert.strictEqual(inviteeUser.customClaims?.orgId, orgId);
  assert.strictEqual(inviteeUser.customClaims?.role, "staff");
  console.log("OK: custom claims set on the invitee.");

  const memberSnap = await db.collection("orgs").doc(orgId).collection("members").doc(invitee.uid).get();
  assert.strictEqual(memberSnap.exists, true);
  assert.strictEqual(memberSnap.data().role, "staff");
  console.log("OK: membership doc created.\n");

  console.log("--- Already-accepted invite cannot be reused ---");
  await expectHttpsError(
    acceptInviteHandler(fakeRequest({ uid: invitee.uid, token: { email: "invitee@example.com" } }, { orgId, token })),
    "failed-precondition"
  );
  console.log("OK: reuse rejected.\n");

  console.log("--- Staff (not owner/admin) cannot invite others ---");
  await expectHttpsError(
    createInviteHandler(
      fakeRequest({ uid: invitee.uid, token: { email: "invitee@example.com", orgId, role: "staff" } }, { orgId, email: "someone-else@example.com", role: "staff" })
    ),
    "permission-denied"
  );
  console.log("OK: staff role cannot create invites.\n");

  console.log("All assertions passed.");
  process.exit(0);
}

main().catch((err) => {
  console.error("\nSMOKE TEST FAILED:", err);
  process.exit(1);
});
