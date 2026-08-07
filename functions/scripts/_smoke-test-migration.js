#!/usr/bin/env node
/**
 * Throwaway smoke test for migrate-to-orgs.js — NOT part of the deployed
 * Functions codebase, not referenced by index.ts, exists purely to prove
 * the migration script actually works before it's ever pointed at
 * production. Run only via emulators:exec (see package.json's
 * "test:migration" script) — never against a real project.
 *
 * Seeds fake pre-migration data (one Auth emulator user, one root-level
 * event with an attendee), runs the real CLI script as a child process in
 * dry-run mode then --execute mode, and asserts the org-scoped copy landed
 * correctly with the original left untouched.
 */

const assert = require("assert");
const { execFileSync } = require("child_process");
const path = require("path");
const admin = require("firebase-admin");

async function main() {
  if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw new Error("Refusing to run outside the emulator — set via `firebase emulators:exec`.");
  }

  admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "sabha-hq" });
  const db = admin.firestore();
  const auth = admin.auth();

  console.log("Seeding fake pre-migration data...");
  const fakeAdmin = await auth.createUser({
    email: "admin@example.com",
    password: "smoke-test-password-123",
  });

  const eventRef = db.collection("events").doc("evt_smoke_test");
  await eventRef.set({ title: "Smoke Test Event", date: admin.firestore.Timestamp.now(), location: "Test Hall" });
  await eventRef.collection("attendees").doc("att_smoke_test").set({
    name: "Test Guest",
    phone: "9876543210",
    email: "guest@example.com",
    role: "guest",
    isCheckedIn: true,
  });

  const scriptPath = path.join(__dirname, "migrate-to-orgs.js");
  const env = { ...process.env };

  console.log("\n--- Dry run ---");
  const dryRunOutput = execFileSync("node", [scriptPath, "--org-id=unpuzzle"], { env }).toString();
  console.log(dryRunOutput);
  assert.match(dryRunOutput, /DRY RUN/, "expected dry run banner");
  assert.match(dryRunOutput, /Events:\s+1 ->/, "expected to see 1 event in dry run report");

  const dryRunCheck = await db.collection("orgs").doc("unpuzzle").get();
  assert.strictEqual(dryRunCheck.exists, false, "dry run must not have written orgs/unpuzzle");

  console.log("--- Execute ---");
  const executeOutput = execFileSync("node", [scriptPath, "--org-id=unpuzzle", "--execute"], { env }).toString();
  console.log(executeOutput);
  assert.match(executeOutput, /EXECUTE \(writing\)/, "expected execute banner");

  console.log("--- Verifying result ---");
  const orgSnap = await db.collection("orgs").doc("unpuzzle").get();
  assert.strictEqual(orgSnap.exists, true, "orgs/unpuzzle should exist after execute");
  assert.strictEqual(orgSnap.data().name, "Unpuzzle");

  const memberSnap = await db.collection("orgs").doc("unpuzzle").collection("members").doc(fakeAdmin.uid).get();
  assert.strictEqual(memberSnap.exists, true, "the password-auth user should be a member");
  assert.strictEqual(memberSnap.data().role, "owner");

  const migratedEvent = await db.collection("orgs").doc("unpuzzle").collection("events").doc("evt_smoke_test").get();
  assert.strictEqual(migratedEvent.exists, true, "event should be copied under the org");
  assert.strictEqual(migratedEvent.data().title, "Smoke Test Event");

  const migratedAttendee = await migratedEvent.ref.collection("attendees").doc("att_smoke_test").get();
  assert.strictEqual(migratedAttendee.exists, true, "attendee should be copied under the org-scoped event");
  assert.strictEqual(migratedAttendee.data().orgId, "unpuzzle", "attendee should be stamped with orgId");
  assert.strictEqual(migratedAttendee.data().phone, "9876543210", "attendee's original fields preserved");

  const originalEventStillThere = await db.collection("events").doc("evt_smoke_test").get();
  assert.strictEqual(originalEventStillThere.exists, true, "original root-level event must be left untouched (copy, not move)");

  console.log("\nAll assertions passed.");
  process.exit(0);
}

main().catch((err) => {
  console.error("\nSMOKE TEST FAILED:", err);
  process.exit(1);
});
