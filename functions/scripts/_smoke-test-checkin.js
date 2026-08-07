#!/usr/bin/env node
/**
 * Throwaway smoke test for checkInHandler/registerWalkInHandler
 * (functions/src/checkIn.ts) — NOT part of the deployed Functions
 * codebase. Run via `npm run test:checkin`, which uses `firebase
 * emulators:exec` against the Firestore emulator only (these handlers
 * don't touch Auth — authorization is decided from the token claims
 * already on the CallableRequest, same as the rules tests).
 *
 * Calls the exported *handler* functions directly with a hand-built
 * CallableRequest, same pattern as _smoke-test-invites.js.
 */

const assert = require("assert");
const admin = require("firebase-admin");
const { checkInHandler, registerWalkInHandler } = require("../lib/checkIn");

function guestRequest(uid, orgId, eventId, data) {
  return {
    auth: {
      uid,
      token: { firebase: { sign_in_provider: "anonymous" }, guestOrgId: orgId, guestEventId: eventId },
    },
    data,
  };
}

function ownerRequest(uid, orgId, data) {
  return {
    auth: {
      uid,
      token: { firebase: { sign_in_provider: "password" }, orgId, role: "owner" },
    },
    data,
  };
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

  const orgId = "unpuzzle";
  const eventId = "evt-checkin-smoke";
  const otherEventId = "evt-checkin-smoke-2";

  await db.doc(`orgs/${orgId}`).set({ name: "Unpuzzle" });
  await db.doc(`orgs/${orgId}/events/${eventId}`).set({ title: "Smoke Event" });
  await db.doc(`orgs/${orgId}/events/${otherEventId}`).set({ title: "A Different Event" });

  // Pre-registered guest, phone stored with a +91 prefix — same scenario
  // as the original phone-format bug: someone imported with a country
  // code, the kiosk enters bare 10 digits.
  await db.doc(`orgs/${orgId}/events/${eventId}/attendees/pre-reg-1`).set({
    eventId,
    orgId,
    name: "Pre-Registered Guest",
    phone: "+919876543210",
    email: "prereg@example.com",
    role: "guest",
    isCheckedIn: false,
  });

  console.log("--- Authorization ---");
  await expectHttpsError(
    checkInHandler(guestRequest("guest-wrong-event", orgId, otherEventId, { orgId, eventId, phone: "9876543210" })),
    "permission-denied"
  );
  console.log("OK: a guest bound to a DIFFERENT event is rejected.\n");

  console.log("--- Phone format tolerance (task #1's bug, now enforced server-side) ---");
  const result1 = await checkInHandler(
    guestRequest("guest-1", orgId, eventId, { orgId, eventId, phone: "9876543210" })
  );
  assert.strictEqual(result1.found, true);
  assert.strictEqual(result1.attendee.name, "Pre-Registered Guest");
  assert.strictEqual(result1.attendee.isCheckedIn, true);
  assert.strictEqual(result1.attendee.phone, "9876543210", "should self-heal to canonical 10-digit form");
  assert.ok(typeof result1.attendee.checkInTime === "string", "checkInTime should be an ISO string, not a raw Timestamp");
  console.log("OK: bare 10 digits found a guest stored with a +91 prefix, and self-healed the stored phone.\n");

  console.log("--- Already checked in (welcome back) ---");
  const result2 = await checkInHandler(
    guestRequest("guest-1", orgId, eventId, { orgId, eventId, phone: "9876543210" })
  );
  assert.strictEqual(result2.found, true);
  assert.strictEqual(result2.attendee.isCheckedIn, true);
  console.log("OK: re-checking in an already-checked-in guest returns them, doesn't error.\n");

  console.log("--- Not found -> walk-in required ---");
  const result3 = await checkInHandler(
    guestRequest("guest-2", orgId, eventId, { orgId, eventId, phone: "1111111111" })
  );
  assert.strictEqual(result3.found, false);
  assert.strictEqual(result3.attendee, undefined);
  console.log("OK: unknown phone returns found:false, not an error.\n");

  console.log("--- Walk-in registration ---");
  const walkIn = await registerWalkInHandler(
    guestRequest("guest-2", orgId, eventId, {
      orgId,
      eventId,
      phone: "1111111111",
      name: "Walk In Guest",
      email: "walkin@example.com",
      companyName: "Acme",
      designation: "Founder",
      industry: "Fintech",
    })
  );
  assert.strictEqual(walkIn.name, "Walk In Guest");
  assert.strictEqual(walkIn.role, "participant");
  assert.strictEqual(walkIn.isCheckedIn, true);
  assert.strictEqual(walkIn.phone, "1111111111");
  const walkInDoc = await db.doc(`orgs/${orgId}/events/${eventId}/attendees/${walkIn.id}`).get();
  assert.strictEqual(walkInDoc.exists, true);
  console.log("OK: walk-in registered, checked in, and actually persisted.\n");

  console.log("--- Org members can also check people in directly (not just guest sessions) ---");
  const staffResult = await checkInHandler(
    ownerRequest("owner-1", orgId, { orgId, eventId, phone: "1111111111" })
  );
  assert.strictEqual(staffResult.found, true);
  console.log("OK: an owner/admin/staff session is authorized too.\n");

  console.log("--- Rate limiting ---");
  for (let i = 0; i < 8; i++) {
    await checkInHandler(guestRequest("guest-ratelimit", orgId, eventId, { orgId, eventId, phone: `999999999${i}` }));
  }
  await expectHttpsError(
    checkInHandler(guestRequest("guest-ratelimit", orgId, eventId, { orgId, eventId, phone: "9999999999" })),
    "resource-exhausted"
  );
  console.log("OK: the 9th attempt within a minute is throttled.\n");

  console.log("--- Audit log ---");
  const logSnap = await db.collection(`orgs/${orgId}/events/${eventId}/checkInLog`).get();
  assert.ok(logSnap.size >= 5, `expected several logged attempts, got ${logSnap.size}`);
  const results = logSnap.docs.map((d) => d.data().result);
  assert.ok(results.includes("checked_in"));
  assert.ok(results.includes("already_checked_in"));
  assert.ok(results.includes("not_found"));
  assert.ok(results.includes("walk_in_registered"));
  console.log(`OK: ${logSnap.size} attempts logged, covering every result type.\n`);

  console.log("All assertions passed.");
  process.exit(0);
}

main().catch((err) => {
  console.error("\nSMOKE TEST FAILED:", err);
  process.exit(1);
});
