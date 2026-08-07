#!/usr/bin/env node
/**
 * Proves firestore.rules actually enforces org isolation — not just that
 * the happy path works, but that the dangerous case (org A reading org
 * B's data, or one event's guest reading another event's attendees within
 * the SAME org) is denied. Run via `npm run test:rules`, which starts
 * only the Firestore emulator (rules don't touch Auth) via
 * `firebase emulators:exec`.
 *
 * Uses @firebase/rules-unit-testing's authenticatedContext() to simulate
 * arbitrary custom claims directly — no need to create real Firebase Auth
 * users just to test rule logic (unlike the invites/migration smoke
 * tests, which exercise real Admin SDK claim-setting and so do need real
 * users).
 */

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");

const RULES_PATH = path.join(__dirname, "..", "..", "firestore.rules");

async function seed(testEnv) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    await db.collection("orgs").doc("org-a").set({ name: "Org A" });
    await db.collection("orgs").doc("org-b").set({ name: "Org B" });

    await db.collection("orgs").doc("org-a").collection("members").doc("owner-a").set({
      email: "owner-a@example.com",
      role: "owner",
    });

    await db.doc("orgs/org-a/events/evt-a").set({ title: "Org A Event", location: "Hall A" });
    await db.doc("orgs/org-a/events/evt-a2").set({ title: "Org A Second Event", location: "Hall A2" });
    await db.doc("orgs/org-b/events/evt-b").set({ title: "Org B Event", location: "Hall B" });

    await db.doc("orgs/org-a/events/evt-a/attendees/att-a").set({ name: "A Attendee", phone: "1111111111" });
    await db.doc("orgs/org-a/events/evt-a2/attendees/att-a2").set({ name: "A2 Attendee", phone: "2222222222" });
    await db.doc("orgs/org-b/events/evt-b/attendees/att-b").set({ name: "B Attendee", phone: "3333333333" });

    await db.doc("orgs/org-a/invites/tok123").set({ email: "invitee@example.com", role: "staff", status: "pending" });
  });
}

function ownerA(testEnv) {
  return testEnv.authenticatedContext("owner-a", {
    firebase: { sign_in_provider: "password", identities: {} },
    orgId: "org-a",
    role: "owner",
  });
}

function staffA(testEnv) {
  return testEnv.authenticatedContext("staff-a", {
    firebase: { sign_in_provider: "password", identities: {} },
    orgId: "org-a",
    role: "staff",
  });
}

function ownerB(testEnv) {
  return testEnv.authenticatedContext("owner-b", {
    firebase: { sign_in_provider: "password", identities: {} },
    orgId: "org-b",
    role: "owner",
  });
}

// A guest who checked into org-a's evt-a specifically (via beginGuestSession).
function guestOfEvtA(testEnv) {
  return testEnv.authenticatedContext("guest-1", {
    firebase: { sign_in_provider: "anonymous", identities: {} },
    guestOrgId: "org-a",
    guestEventId: "evt-a",
  });
}

let passed = 0;
async function check(name, fn) {
  await fn();
  passed += 1;
  console.log(`OK: ${name}`);
}

async function main() {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error("Refusing to run outside the emulator — set via `firebase emulators:exec`.");
  }

  const [host, portStr] = process.env.FIRESTORE_EMULATOR_HOST.split(":");
  const testEnv = await initializeTestEnvironment({
    projectId: "sabha-hq-rules-test",
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host,
      port: Number(portStr),
    },
  });

  try {
    await seed(testEnv);

    // --- Org isolation: the core guarantee this task exists to prove ---
    await check("org A owner can read org A's event", async () => {
      await assertSucceeds(ownerA(testEnv).firestore().doc("orgs/org-a/events/evt-a").get());
    });

    await check("event docs are public read regardless of org (no PII, needed pre-auth)", async () => {
      // Deliberate, not a leak: same reasoning as the pre-migration rules
      // — the check-in screen needs the event title before any auth
      // completes. The isolation guarantee is about attendees (PII) and
      // about writes, asserted below.
      await assertSucceeds(ownerA(testEnv).firestore().doc("orgs/org-b/events/evt-b").get());
    });

    await check("org A owner CANNOT update org B's event", async () => {
      await assertFails(
        ownerA(testEnv).firestore().doc("orgs/org-b/events/evt-b").set({ title: "Hijacked" }, { merge: true })
      );
    });

    await check("org A owner CANNOT read org B's attendees", async () => {
      await assertFails(ownerA(testEnv).firestore().doc("orgs/org-b/events/evt-b/attendees/att-b").get());
    });

    await check("org A owner CANNOT write into org B's attendees", async () => {
      await assertFails(
        ownerA(testEnv)
          .firestore()
          .doc("orgs/org-b/events/evt-b/attendees/forged")
          .set({ name: "Forged", phone: "0000000000" })
      );
    });

    await check("org A owner CANNOT delete org B's event", async () => {
      await assertFails(ownerA(testEnv).firestore().doc("orgs/org-b/events/evt-b").delete());
    });

    await check("org B owner can operate normally inside org B", async () => {
      await assertSucceeds(ownerB(testEnv).firestore().doc("orgs/org-b/events/evt-b").get());
    });

    // --- Role scoping within one org ---
    await check("staff can check in an attendee (create/update)", async () => {
      await assertSucceeds(
        staffA(testEnv)
          .firestore()
          .doc("orgs/org-a/events/evt-a/attendees/att-a")
          .set({ name: "A Attendee", phone: "1111111111", isCheckedIn: true }, { merge: true })
      );
    });

    await check("staff CANNOT delete an attendee (owner/admin only)", async () => {
      await assertFails(staffA(testEnv).firestore().doc("orgs/org-a/events/evt-a/attendees/att-a").delete());
    });

    await check("staff CANNOT create a new event (owner/admin only)", async () => {
      await assertFails(
        staffA(testEnv).firestore().doc("orgs/org-a/events/evt-new").set({ title: "Rogue Event" })
      );
    });

    await check("owner CAN delete an attendee", async () => {
      await assertSucceeds(ownerA(testEnv).firestore().doc("orgs/org-a/events/evt-a2/attendees/att-a2").delete());
    });

    // --- Agenda (task #8) ---
    await check("anyone unauthenticated can read the agenda (no PII, pre-auth)", async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc("orgs/org-a/events/evt-a/scheduleItems/item-1").set({ title: "Opening Keynote" });
      });
      await assertSucceeds(
        testEnv.unauthenticatedContext().firestore().doc("orgs/org-a/events/evt-a/scheduleItems/item-1").get()
      );
    });

    await check("staff CANNOT write the agenda (owner/admin only)", async () => {
      await assertFails(
        staffA(testEnv).firestore().doc("orgs/org-a/events/evt-a/scheduleItems/item-2").set({ title: "Rogue Item" })
      );
    });

    await check("owner CAN write the agenda", async () => {
      await assertSucceeds(
        ownerA(testEnv).firestore().doc("orgs/org-a/events/evt-a/scheduleItems/item-2").set({ title: "Lunch" })
      );
    });

    // --- Guest sessions: the cross-EVENT case, not just cross-org ---
    await check("a guest bound to evt-a can read evt-a's attendees", async () => {
      await assertSucceeds(guestOfEvtA(testEnv).firestore().doc("orgs/org-a/events/evt-a/attendees/att-a").get());
    });

    await check(
      "a guest CANNOT write attendees directly anymore (task #6: goes through checkIn/registerWalkIn instead)",
      async () => {
        await assertFails(
          guestOfEvtA(testEnv)
            .firestore()
            .doc("orgs/org-a/events/evt-a/attendees/walkin-1")
            .set({ name: "Walk In", phone: "4444444444" })
        );
        await assertFails(
          guestOfEvtA(testEnv)
            .firestore()
            .doc("orgs/org-a/events/evt-a/attendees/att-a")
            .set({ isCheckedIn: true }, { merge: true })
        );
      }
    );

    await check(
      "a guest bound to evt-a CANNOT read evt-a2's attendees (same org, different event)",
      async () => {
        await assertFails(guestOfEvtA(testEnv).firestore().doc("orgs/org-a/events/evt-a2/attendees/att-a2").get());
      }
    );

    await check("a guest bound to evt-a CANNOT read org B's attendees at all", async () => {
      await assertFails(guestOfEvtA(testEnv).firestore().doc("orgs/org-b/events/evt-b/attendees/att-b").get());
    });

    await check("a guest CANNOT delete an attendee record", async () => {
      await assertFails(guestOfEvtA(testEnv).firestore().doc("orgs/org-a/events/evt-a/attendees/att-a").delete());
    });

    // --- Public / unauthenticated access ---
    await check("anyone unauthenticated can read event details (no PII)", async () => {
      await assertSucceeds(testEnv.unauthenticatedContext().firestore().doc("orgs/org-a/events/evt-a").get());
    });

    await check("unauthenticated cannot read attendees", async () => {
      await assertFails(testEnv.unauthenticatedContext().firestore().doc("orgs/org-a/events/evt-a/attendees/att-a").get());
    });

    await check("unauthenticated cannot read the org doc itself", async () => {
      await assertFails(testEnv.unauthenticatedContext().firestore().doc("orgs/org-a").get());
    });

    // --- Locked-down collections ---
    await check("even the owner cannot delete the org doc (no flow exists yet)", async () => {
      await assertFails(ownerA(testEnv).firestore().doc("orgs/org-a").delete());
    });

    await check("even the owner cannot read invites directly (Admin-SDK only)", async () => {
      await assertFails(ownerA(testEnv).firestore().doc("orgs/org-a/invites/tok123").get());
    });

    await check("even the owner cannot read the check-in audit log (Admin-SDK only)", async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc("orgs/org-a/events/evt-a/checkInLog/entry-1").set({ uid: "guest-1", result: "checked_in" });
      });
      await assertFails(ownerA(testEnv).firestore().doc("orgs/org-a/events/evt-a/checkInLog/entry-1").get());
    });

    await check("even the owner cannot read rate-limit counters (Admin-SDK only)", async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc("orgs/org-a/events/evt-a/checkInRateLimits/guest-1").set({ attempts: [] });
      });
      await assertFails(ownerA(testEnv).firestore().doc("orgs/org-a/events/evt-a/checkInRateLimits/guest-1").get());
    });

    await check("nobody can read the legacy flat events/* tree", async () => {
      // Simulates the pre-migration data migrate-to-orgs.js copies FROM
      // but never deletes — confirms it's unreachable by any client now.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc("events/legacy-evt").set({ title: "Legacy" });
      });
      await assertFails(ownerA(testEnv).firestore().doc("events/legacy-evt").get());
    });

    console.log(`\nAll ${passed} assertions passed.`);
  } finally {
    await testEnv.cleanup();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(`\nRULES TEST FAILED after ${passed} passing check(s):`, err);
    process.exit(1);
  });
