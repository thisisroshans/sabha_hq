#!/usr/bin/env node
/**
 * Throwaway smoke test for notifyAdminsOfCheckIn / isNewCheckIn
 * (functions/src/notifications.ts) — NOT part of the deployed Functions
 * codebase. Run via `npm run test:notifications`, which uses `firebase
 * emulators:exec` against the Firestore emulator only.
 *
 * Calls the exported functions directly (same pattern as
 * _smoke-test-checkin.js) with a fake FCM sender injected, so it proves
 * WHO gets pushed and WHAT they're sent without needing a real FCM
 * project or device.
 */

const assert = require("assert");
const admin = require("firebase-admin");
const { notifyAdminsOfCheckIn, isNewCheckIn, roleLabel } = require("../lib/notifications");

/** Records every multicast it's asked to send; tokens listed in `dead`
 * fail the way FCM fails an uninstalled app's token. */
function fakeSender(dead = []) {
  const calls = [];
  return {
    calls,
    async sendEachForMulticast(message) {
      calls.push(message);
      const responses = message.tokens.map((token) =>
        dead.includes(token)
          ? { success: false, error: { code: "messaging/registration-token-not-registered" } }
          : { success: true, messageId: `msg-${token}` }
      );
      return {
        responses,
        successCount: responses.filter((r) => r.success).length,
        failureCount: responses.filter((r) => !r.success).length,
      };
    },
  };
}

async function main() {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error("Refusing to run outside the emulator — set via `firebase emulators:exec`.");
  }

  admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "sabha-hq" });
  const db = admin.firestore();

  console.log("--- isNewCheckIn: fires exactly once per check-in ---");
  assert.strictEqual(isNewCheckIn({ isCheckedIn: false }, { isCheckedIn: true }), true, "checkIn callable flip");
  assert.strictEqual(isNewCheckIn(undefined, { isCheckedIn: true }), true, "registerWalkIn create");
  assert.strictEqual(isNewCheckIn({ isCheckedIn: true }, { isCheckedIn: true, phone: "9876543210" }), false, "welcome-back / phone self-heal");
  assert.strictEqual(isNewCheckIn(undefined, { isCheckedIn: false }), false, "CSV import / manual add");
  assert.strictEqual(isNewCheckIn({ isCheckedIn: true }, undefined), false, "delete");
  assert.strictEqual(isNewCheckIn({ isCheckedIn: true }, { isCheckedIn: false }), false, "un-check-in");
  console.log("OK\n");

  console.log("--- roleLabel: guests are Movers, participants are Pitchers ---");
  assert.strictEqual(roleLabel("guest"), "Mover");
  assert.strictEqual(roleLabel("participant"), "Pitcher");
  assert.strictEqual(roleLabel("Participant "), "Pitcher");
  assert.strictEqual(roleLabel(undefined), "Mover");
  console.log("OK\n");

  const orgId = "notify-org";
  const eventId = "evt-notify";
  await db.doc(`orgs/${orgId}`).set({ name: "Notify Org" });
  await db.doc(`orgs/${orgId}/events/${eventId}`).set({ title: "Demo Day" });
  await db.doc(`orgs/${orgId}/members/owner-1`).set({ email: "owner@example.com", role: "owner" });
  await db.doc(`orgs/${orgId}/members/admin-1`).set({ email: "admin@example.com", role: "admin" });
  await db.doc(`orgs/${orgId}/members/staff-1`).set({ email: "staff@example.com", role: "staff" });
  const device = { platform: "android", updatedAt: admin.firestore.FieldValue.serverTimestamp() };
  await db.doc(`orgs/${orgId}/members/owner-1/devices/tok-owner-phone`).set(device);
  await db.doc(`orgs/${orgId}/members/owner-1/devices/tok-owner-laptop`).set({ ...device, platform: "web" });
  await db.doc(`orgs/${orgId}/members/admin-1/devices/tok-admin-phone`).set(device);
  // A laptop two admins have both signed in on — should still get ONE push.
  await db.doc(`orgs/${orgId}/members/admin-1/devices/tok-shared`).set({ ...device, platform: "web" });
  await db.doc(`orgs/${orgId}/members/owner-1/devices/tok-shared`).set({ ...device, platform: "web" });
  await db.doc(`orgs/${orgId}/members/staff-1/devices/tok-staff-phone`).set(device);

  console.log("--- Every owner/admin device is pushed, staff are not ---");
  const sender = fakeSender(["tok-admin-phone"]);
  const result = await notifyAdminsOfCheckIn(
    orgId,
    eventId,
    "att-1",
    { name: "Asha Rao", role: "participant", companyName: "Acme", isCheckedIn: true },
    sender
  );
  assert.strictEqual(sender.calls.length, 1);
  const message = sender.calls[0];
  assert.deepStrictEqual(
    [...message.tokens].sort(),
    ["tok-admin-phone", "tok-owner-laptop", "tok-owner-phone", "tok-shared"],
    "owner + admin devices, deduped, no staff"
  );
  assert.strictEqual(message.notification.title, "Asha Rao checked in");
  assert.strictEqual(message.notification.body, "Pitcher · Demo Day · Acme");
  assert.deepStrictEqual(message.data, { type: "check_in", orgId, eventId, attendeeId: "att-1" });
  assert.strictEqual(message.android.notification.channelId, "check_ins");
  assert.strictEqual(message.webpush.fcmOptions.link, "https://sabha-hq.web.app/dashboard/live");
  assert.deepStrictEqual(result, { sent: 3, failed: 1, removedDevices: 1 });
  console.log("OK: 4 unique owner/admin devices pushed (shared laptop once), staff skipped, Pitcher label used.\n");

  console.log("--- A dead token's device doc is cleaned up ---");
  const deadDoc = await db.doc(`orgs/${orgId}/members/admin-1/devices/tok-admin-phone`).get();
  assert.strictEqual(deadDoc.exists, false);
  const liveDoc = await db.doc(`orgs/${orgId}/members/owner-1/devices/tok-owner-phone`).get();
  assert.strictEqual(liveDoc.exists, true);
  console.log("OK: unregistered token's device doc deleted, working ones kept.\n");

  console.log("--- Mover label for guests ---");
  const moverSender = fakeSender();
  await notifyAdminsOfCheckIn(orgId, eventId, "att-2", { name: "Ravi", role: "guest", isCheckedIn: true }, moverSender);
  assert.strictEqual(moverSender.calls[0].notification.body, "Mover · Demo Day");
  console.log("OK\n");

  console.log("--- An org with no owner/admin devices sends nothing ---");
  const quietOrg = "quiet-org";
  await db.doc(`orgs/${quietOrg}`).set({ name: "Quiet" });
  await db.doc(`orgs/${quietOrg}/members/owner-q`).set({ email: "q@example.com", role: "owner" });
  await db.doc(`orgs/${quietOrg}/members/staff-q/devices/tok-staff-q`).set(device);
  await db.doc(`orgs/${quietOrg}/members/staff-q`).set({ email: "sq@example.com", role: "staff" });
  const quietSender = fakeSender();
  const quietResult = await notifyAdminsOfCheckIn(quietOrg, "evt-q", "att-q", { name: "X", isCheckedIn: true }, quietSender);
  assert.strictEqual(quietSender.calls.length, 0);
  assert.deepStrictEqual(quietResult, { sent: 0, failed: 0, removedDevices: 0 });
  console.log("OK: no FCM call made at all.\n");

  console.log("All notification smoke tests passed.");
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("NOTIFICATION SMOKE TEST FAILED:", err);
    process.exit(1);
  });
