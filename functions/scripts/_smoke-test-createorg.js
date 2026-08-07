#!/usr/bin/env node
/**
 * Throwaway smoke test for createOrgHandler (functions/src/orgs.ts) — NOT
 * part of the deployed Functions codebase. Run via `npm run test:orgs`
 * against the Firestore + Auth emulators (real Auth users needed here,
 * unlike the rules tests, since this exercises real Admin SDK claim-
 * setting via admin.auth().setCustomUserClaims).
 */

const assert = require("assert");
const admin = require("firebase-admin");
const { createOrgHandler } = require("../lib/orgs");

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

  console.log("--- Unauthenticated is rejected ---");
  await expectHttpsError(createOrgHandler(fakeRequest(undefined, { orgName: "Acme" })), "unauthenticated");
  console.log("OK.\n");

  console.log("--- Empty org name is rejected ---");
  const freshUser = await auth.createUser({ email: "founder@example.com", password: "smoke-test-123" });
  await expectHttpsError(
    createOrgHandler(fakeRequest({ uid: freshUser.uid, token: {} }, { orgName: "  " })),
    "invalid-argument"
  );
  console.log("OK.\n");

  console.log("--- Happy path ---");
  const result = await createOrgHandler(
    fakeRequest({ uid: freshUser.uid, token: { email: "founder@example.com" } }, { orgName: "Unpuzzle" })
  );
  assert.ok(result.orgId, "expected an orgId back");
  console.log(`OK: org created, id=${result.orgId}`);

  const orgSnap = await db.collection("orgs").doc(result.orgId).get();
  assert.strictEqual(orgSnap.exists, true);
  assert.strictEqual(orgSnap.data().name, "Unpuzzle");
  assert.strictEqual(orgSnap.data().plan, "free", "should default to the free plan with no billing wired up");
  console.log("OK: org doc has the right shape (name + free plan).");

  const memberSnap = await db.collection("orgs").doc(result.orgId).collection("members").doc(freshUser.uid).get();
  assert.strictEqual(memberSnap.exists, true);
  assert.strictEqual(memberSnap.data().role, "owner");
  console.log("OK: caller is an owner member.");

  const userRecord = await auth.getUser(freshUser.uid);
  assert.strictEqual(userRecord.customClaims?.orgId, result.orgId);
  assert.strictEqual(userRecord.customClaims?.role, "owner");
  console.log("OK: custom claims set on the caller.\n");

  console.log("--- Someone who already belongs to an org is rejected (one org per admin) ---");
  await expectHttpsError(
    createOrgHandler(
      fakeRequest({ uid: freshUser.uid, token: { orgId: result.orgId, role: "owner" } }, { orgName: "Second Org" })
    ),
    "already-exists"
  );
  console.log("OK.\n");

  console.log("All assertions passed.");
  process.exit(0);
}

main().catch((err) => {
  console.error("\nSMOKE TEST FAILED:", err);
  process.exit(1);
});
