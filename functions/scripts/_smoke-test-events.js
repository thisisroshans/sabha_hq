#!/usr/bin/env node
/**
 * Throwaway smoke test for functions/src/events.ts's createEvent — NOT
 * part of the deployed Functions codebase. Run via `npm run test:events`
 * against the Firestore emulator only (auth is decided from token claims
 * already on the CallableRequest, same as checkIn.ts's tests — no real
 * Auth users needed).
 */

const assert = require("assert");
const admin = require("firebase-admin");
const { createEventHandler } = require("../lib/events");

function ownerRequest(orgId, data) {
  return { auth: { uid: "owner-1", token: { orgId, role: "owner" } }, data };
}

function staffRequest(orgId, data) {
  return { auth: { uid: "staff-1", token: { orgId, role: "staff" } }, data };
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
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error("Refusing to run outside the emulator — set via `firebase emulators:exec`.");
  }

  admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "sabha-hq" });
  const db = admin.firestore();

  const orgId = "org-events-smoke";
  await db.doc(`orgs/${orgId}`).set({
    name: "Events Smoke Org",
    status: "active",
    limits: { maxTeamMembers: 5, maxEvents: 2, maxAttendeesPerEvent: 250, checkInRateLimitPerMinute: 8 },
  });

  console.log("--- Staff (not owner/admin) cannot create an event ---");
  await expectHttpsError(
    createEventHandler(staffRequest(orgId, { orgId, title: "Rogue", location: "Nowhere", dateIso: new Date().toISOString() })),
    "permission-denied"
  );
  console.log("OK.\n");

  console.log("--- Happy path, up to the limit ---");
  const event1 = await createEventHandler(
    ownerRequest(orgId, { orgId, title: "Event One", location: "Hall A", dateIso: new Date().toISOString() })
  );
  assert.ok(event1.id);
  const event2 = await createEventHandler(
    ownerRequest(orgId, { orgId, title: "Event Two", location: "Hall B", dateIso: new Date().toISOString() })
  );
  assert.ok(event2.id);
  console.log("OK: created 2 events, at the maxEvents=2 limit.\n");

  console.log("--- maxEvents is actually enforced on the 3rd ---");
  await expectHttpsError(
    createEventHandler(ownerRequest(orgId, { orgId, title: "Event Three", location: "Hall C", dateIso: new Date().toISOString() })),
    "resource-exhausted"
  );
  console.log("OK: rejected past the limit.\n");

  console.log("--- Document shape matches Event.toJson()'s defaults ---");
  const doc = await db.doc(`orgs/${orgId}/events/${event1.id}`).get();
  const data = doc.data();
  assert.strictEqual(data.title, "Event One");
  assert.deepStrictEqual(data.branding, { primaryColor: "#673AB7", logoUrl: "" });
  assert.strictEqual(data.totalRegistered, 0);
  assert.strictEqual(data.totalCheckedIn, 0);
  console.log("OK.\n");

  console.log("--- A suspended org cannot create events ---");
  await db.doc(`orgs/${orgId}`).update({ status: "suspended" });
  await expectHttpsError(
    createEventHandler(ownerRequest(orgId, { orgId, title: "Nope", location: "Nowhere", dateIso: new Date().toISOString() })),
    "failed-precondition"
  );
  console.log("OK.\n");

  console.log("--- Validation ---");
  await db.doc(`orgs/${orgId}`).update({ status: "active" });
  await expectHttpsError(
    createEventHandler(ownerRequest(orgId, { orgId, title: "", location: "Hall A", dateIso: new Date().toISOString() })),
    "invalid-argument"
  );
  await expectHttpsError(
    createEventHandler(ownerRequest(orgId, { orgId, title: "Has Title", location: "Hall A", dateIso: "not-a-date" })),
    "invalid-argument"
  );
  console.log("OK: empty title and invalid date both rejected (validation runs before the maxEvents/suspension checks, so this holds even though the org is already at its limit).\n");

  console.log("All assertions passed.");
  process.exit(0);
}

main().catch((err) => {
  console.error("\nSMOKE TEST FAILED:", err);
  process.exit(1);
});
