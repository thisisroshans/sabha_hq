#!/usr/bin/env node
/**
 * Throwaway smoke test for functions/src/platform.ts — NOT part of the
 * deployed Functions codebase. Run via `npm run test:platform` against
 * the Firestore emulator (rules/claims-only checks, no Auth users needed —
 * same pattern as _test-firestore-rules.js).
 *
 * Calls the exported *handler* functions directly with a hand-built
 * CallableRequest, same pattern as every other smoke test in this
 * directory. Specifically proves the count()-aggregation usage numbers
 * are actually correct, not just that the functions don't throw.
 */

const assert = require("assert");
const admin = require("firebase-admin");
const {
  getPlatformOverviewHandler,
  getOrgDetailHandler,
  updateOrgLimitsHandler,
  setOrgStatusHandler,
  getPlatformAuditLogHandler,
} = require("../lib/platform");

function platformOwnerRequest(data) {
  return { auth: { uid: "platform-owner-1", token: { platformRole: "owner" } }, data };
}

function orgOwnerRequest(orgId, data) {
  return { auth: { uid: "org-owner-1", token: { orgId, role: "owner" } }, data };
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

  // --- Seed two orgs with known, distinct usage ------------------------
  await db.doc("orgs/org-a").set({ name: "Org A", plan: "free", status: "active" });
  await db.doc("orgs/org-a/events/evt-a1").set({ title: "Event A1" });
  await db.doc("orgs/org-a/events/evt-a2").set({ title: "Event A2" });
  await db.doc("orgs/org-a/members/u1").set({ email: "a1@example.com", role: "owner" });
  await db.doc("orgs/org-a/members/u2").set({ email: "a2@example.com", role: "staff" });
  await db.doc("orgs/org-a/events/evt-a1/attendees/att1").set({ orgId: "org-a", name: "A" });
  await db.doc("orgs/org-a/events/evt-a2/attendees/att2").set({ orgId: "org-a", name: "B" });
  await db.doc("orgs/org-a/events/evt-a2/attendees/att3").set({ orgId: "org-a", name: "C" });

  await db.doc("orgs/org-b").set({ name: "Org B", plan: "free", status: "active" });
  await db.doc("orgs/org-b/events/evt-b1").set({ title: "Event B1" });
  await db.doc("orgs/org-b/members/u3").set({ email: "b1@example.com", role: "owner" });

  console.log("--- Non-platform-staff callers are rejected everywhere ---");
  await expectHttpsError(getPlatformOverviewHandler(orgOwnerRequest("org-a", {})), "permission-denied");
  await expectHttpsError(getOrgDetailHandler(orgOwnerRequest("org-a", { orgId: "org-a" })), "permission-denied");
  await expectHttpsError(
    updateOrgLimitsHandler(orgOwnerRequest("org-a", { orgId: "org-a", limits: { maxEvents: 999 } })),
    "permission-denied"
  );
  await expectHttpsError(
    setOrgStatusHandler(orgOwnerRequest("org-a", { orgId: "org-a", status: "suspended" })),
    "permission-denied"
  );
  console.log("OK: an org's own owner cannot call any platform function.\n");

  console.log("--- getPlatformOverview: usage math is actually correct ---");
  const overview = await getPlatformOverviewHandler(platformOwnerRequest({}));
  const orgA = overview.orgs.find((o) => o.id === "org-a");
  const orgB = overview.orgs.find((o) => o.id === "org-b");
  assert.ok(orgA && orgB, "expected both seeded orgs in the overview");
  assert.strictEqual(orgA.usage.eventCount, 2);
  assert.strictEqual(orgA.usage.teamMemberCount, 2);
  assert.strictEqual(orgA.usage.attendeeCount, 3, "3 attendees across 2 events, summed via collectionGroup+orgId");
  assert.strictEqual(orgB.usage.eventCount, 1);
  assert.strictEqual(orgB.usage.teamMemberCount, 1);
  assert.strictEqual(orgB.usage.attendeeCount, 0);
  assert.deepStrictEqual(orgA.limits, {
    maxTeamMembers: 5,
    maxEvents: 3,
    maxAttendeesPerEvent: 250,
    checkInRateLimitPerMinute: 8,
  }, "org with no limits map set yet should fall back to DEFAULT_LIMITS");
  console.log("OK: event/member/attendee counts and default-limits fallback all correct.\n");

  console.log("--- getOrgDetail ---");
  const detail = await getOrgDetailHandler(platformOwnerRequest({ orgId: "org-a" }));
  assert.strictEqual(detail.usage.attendeeCount, 3);
  await expectHttpsError(getOrgDetailHandler(platformOwnerRequest({ orgId: "does-not-exist" })), "not-found");
  console.log("OK: single-org detail correct, unknown org rejected.\n");

  console.log("--- updateOrgLimits: partial update + validation + audit log ---");
  const updated = await updateOrgLimitsHandler(
    platformOwnerRequest({ orgId: "org-a", limits: { maxEvents: 10 } })
  );
  assert.strictEqual(updated.limits.maxEvents, 10);
  assert.strictEqual(updated.limits.maxTeamMembers, 5, "unspecified fields should keep their (default) value");

  await expectHttpsError(
    updateOrgLimitsHandler(platformOwnerRequest({ orgId: "org-a", limits: { maxEvents: -1 } })),
    "invalid-argument"
  );
  await expectHttpsError(
    updateOrgLimitsHandler(platformOwnerRequest({ orgId: "org-a", limits: { maxEvents: 1.5 } })),
    "invalid-argument"
  );
  console.log("OK: partial update applied, non-positive-integer values rejected.\n");

  console.log("--- setOrgStatus: suspend + reactivate + audit log ---");
  const suspended = await setOrgStatusHandler(platformOwnerRequest({ orgId: "org-a", status: "suspended" }));
  assert.strictEqual(suspended.status, "suspended");
  const orgASnap = await db.doc("orgs/org-a").get();
  assert.strictEqual(orgASnap.data().status, "suspended");

  const reactivated = await setOrgStatusHandler(platformOwnerRequest({ orgId: "org-a", status: "active" }));
  assert.strictEqual(reactivated.status, "active");
  console.log("OK: suspend and reactivate both persisted correctly.\n");

  console.log("--- getPlatformAuditLog ---");
  const fullLog = await getPlatformAuditLogHandler(platformOwnerRequest({}));
  assert.ok(fullLog.entries.length >= 3, `expected at least 3 logged actions, got ${fullLog.entries.length}`);
  const actions = fullLog.entries.map((e) => e.action);
  assert.ok(actions.includes("update_limits"));
  assert.ok(actions.includes("set_status"));

  const orgAOnly = await getPlatformAuditLogHandler(platformOwnerRequest({ orgId: "org-a" }));
  assert.ok(orgAOnly.entries.every((e) => e.orgId === "org-a"));
  console.log(`OK: ${fullLog.entries.length} audit entries recorded, org-filtering works.\n`);

  console.log("All assertions passed.");
  process.exit(0);
}

main().catch((err) => {
  console.error("\nSMOKE TEST FAILED:", err);
  process.exit(1);
});
