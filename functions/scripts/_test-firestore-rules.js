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

    // orgId mirrors what firestore_refs.dart's attendee converter always
    // writes in production — seeding it here keeps the fixture honest
    // against attendeeDataValid()'s check below.
    await db.doc("orgs/org-a/events/evt-a/attendees/att-a").set({ name: "A Attendee", phone: "1111111111", orgId: "org-a" });
    await db.doc("orgs/org-a/events/evt-a2/attendees/att-a2").set({ name: "A2 Attendee", phone: "2222222222", orgId: "org-a" });
    await db.doc("orgs/org-b/events/evt-b/attendees/att-b").set({ name: "B Attendee", phone: "3333333333", orgId: "org-b" });

    await db.doc("orgs/org-a/invites/tok123").set({ email: "invitee@example.com", role: "staff", status: "pending" });

    // A separate, suspended org — kept apart from org-a/org-b so
    // suspension tests can't accidentally interfere with the rest of the
    // suite, which assumes an active org.
    await db.collection("orgs").doc("org-c").set({ name: "Org C", status: "suspended" });
    await db.doc("orgs/org-c/events/evt-c").set({ title: "Org C Event", location: "Hall C" });
    await db.doc("orgs/org-c/events/evt-c/attendees/att-c").set({ name: "C Attendee", phone: "5555555555" });
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

function platformOwner(testEnv) {
  return testEnv.authenticatedContext("platform-owner-1", {
    firebase: { sign_in_provider: "password", identities: {} },
    platformRole: "owner",
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

    // --- attendeeDataValid(): the denormalised orgId field can't be forged ---
    await check("staff CAN create an attendee tagged with their own org's id", async () => {
      await assertSucceeds(
        staffA(testEnv)
          .firestore()
          .doc("orgs/org-a/events/evt-a/attendees/walkin-legit")
          .set({ name: "Legit Walk-In", phone: "6666666666", orgId: "org-a" })
      );
    });

    await check("staff CANNOT create an attendee tagged with a DIFFERENT org's id", async () => {
      await assertFails(
        staffA(testEnv)
          .firestore()
          .doc("orgs/org-a/events/evt-a/attendees/walkin-forged")
          .set({ name: "Forged", phone: "7777777777", orgId: "org-b" })
      );
    });

    await check("staff CANNOT flip an existing attendee's orgId to another org", async () => {
      await assertFails(
        staffA(testEnv)
          .firestore()
          .doc("orgs/org-a/events/evt-a/attendees/att-a")
          .set({ orgId: "org-b" }, { merge: true })
      );
    });

    await check(
      "NOBODY can create an event directly anymore, not even the owner (moved to the createEvent callable, functions/src/events.ts, so maxEvents can be enforced — rules can't run a count() aggregation)",
      async () => {
        await assertFails(
          staffA(testEnv).firestore().doc("orgs/org-a/events/evt-new").set({ title: "Rogue Event" })
        );
        await assertFails(
          ownerA(testEnv).firestore().doc("orgs/org-a/events/evt-new-2").set({ title: "Even Owner Can't" })
        );
      }
    );

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

    // --- Feedback (task #8): feedbackDataValid() bounds the one field a
    // guest can freely choose (rating), since this is the one collection
    // where an anonymous session gets a direct create path. ---
    await check("a guest CAN submit valid feedback (rating 1-5, optional comment)", async () => {
      await assertSucceeds(
        guestOfEvtA(testEnv)
          .firestore()
          .doc("orgs/org-a/events/evt-a/feedback/fb-good")
          .set({ rating: 4, comment: "Great event", submittedAt: new Date() })
      );
      await assertSucceeds(
        guestOfEvtA(testEnv)
          .firestore()
          .doc("orgs/org-a/events/evt-a/feedback/fb-no-comment")
          .set({ rating: 5, comment: null, submittedAt: new Date() })
      );
    });

    await check("a guest CANNOT submit feedback with an out-of-range or non-numeric rating", async () => {
      await assertFails(
        guestOfEvtA(testEnv)
          .firestore()
          .doc("orgs/org-a/events/evt-a/feedback/fb-zero")
          .set({ rating: 0, comment: null, submittedAt: new Date() })
      );
      await assertFails(
        guestOfEvtA(testEnv)
          .firestore()
          .doc("orgs/org-a/events/evt-a/feedback/fb-six")
          .set({ rating: 6, comment: null, submittedAt: new Date() })
      );
      await assertFails(
        guestOfEvtA(testEnv)
          .firestore()
          .doc("orgs/org-a/events/evt-a/feedback/fb-string")
          .set({ rating: "5", comment: null, submittedAt: new Date() })
      );
    });

    await check("a guest bound to evt-a CANNOT submit feedback for a different event", async () => {
      await assertFails(
        guestOfEvtA(testEnv)
          .firestore()
          .doc("orgs/org-a/events/evt-a2/feedback/fb-wrong-event")
          .set({ rating: 5, comment: null, submittedAt: new Date() })
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

    await check("even the owner cannot write member docs directly (Admin-SDK only, via acceptInvite)", async () => {
      await assertFails(
        ownerA(testEnv)
          .firestore()
          .doc("orgs/org-a/members/self-promoted")
          .set({ email: "sneaky@example.com", role: "owner" })
      );
      // Not even editing an existing member's own role.
      await assertFails(
        ownerA(testEnv).firestore().doc("orgs/org-a/members/owner-a").set({ role: "owner" }, { merge: true })
      );
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

    // --- Platform owner: full READ parity with what an org's own
    // owner/admin can see, across every org — but NOT write access, and
    // NOT the things an org's own owner can't see either (invites,
    // checkInLog) — that's parity, not extra access. ---
    await check("platform owner can read org A's AND org B's docs, members, and attendees", async () => {
      await assertSucceeds(platformOwner(testEnv).firestore().doc("orgs/org-a").get());
      await assertSucceeds(platformOwner(testEnv).firestore().doc("orgs/org-b").get());
      await assertSucceeds(platformOwner(testEnv).firestore().doc("orgs/org-a/members/owner-a").get());
      await assertSucceeds(platformOwner(testEnv).firestore().doc("orgs/org-a/events/evt-a/attendees/att-a").get());
      await assertSucceeds(platformOwner(testEnv).firestore().doc("orgs/org-b/events/evt-b/attendees/att-b").get());
    });

    await check("platform owner does NOT get write access to an org's data (view only)", async () => {
      await assertFails(
        platformOwner(testEnv).firestore().doc("orgs/org-a/events/evt-a/attendees/att-a")
          .set({ isCheckedIn: true }, { merge: true })
      );
      await assertFails(platformOwner(testEnv).firestore().doc("orgs/org-a/events/evt-a").delete());
    });

    await check("platform owner sees only what an org owner CAN see, not extra: invites and check-in log stay closed", async () => {
      await assertFails(platformOwner(testEnv).firestore().doc("orgs/org-a/invites/tok123").get());
      await assertFails(platformOwner(testEnv).firestore().doc("orgs/org-a/events/evt-a/checkInLog/entry-1").get());
    });

    await check("even the platform owner cannot delete an org (no flow exists yet)", async () => {
      await assertFails(platformOwner(testEnv).firestore().doc("orgs/org-a").delete());
    });

    // --- Suspension (org-c, seeded status:'suspended') blocks writes,
    // not reads --- see firestore.rules' orgIsActive() and the
    // PLATFORM DASHBOARD comment for why reads stay open.
    await check("a suspended org's own owner can still READ their data", async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc("orgs/org-c/members/owner-c").set({ email: "owner-c@example.com", role: "owner" });
      });
      await assertSucceeds(platformOwner(testEnv).firestore().doc("orgs/org-c").get()); // sanity: doc exists
      const ownerC = testEnv.authenticatedContext("owner-c", {
        firebase: { sign_in_provider: "password", identities: {} },
        orgId: "org-c",
        role: "owner",
      });
      await assertSucceeds(ownerC.firestore().doc("orgs/org-c/events/evt-c").get());
      await assertSucceeds(ownerC.firestore().doc("orgs/org-c/events/evt-c/attendees/att-c").get());
    });

    await check("a suspended org's owner CANNOT write — event update, attendee update, agenda, org rename all blocked", async () => {
      const ownerC = testEnv.authenticatedContext("owner-c", {
        firebase: { sign_in_provider: "password", identities: {} },
        orgId: "org-c",
        role: "owner",
      });
      await assertFails(ownerC.firestore().doc("orgs/org-c/events/evt-c").set({ title: "Renamed" }, { merge: true }));
      await assertFails(
        ownerC.firestore().doc("orgs/org-c/events/evt-c/attendees/att-c").set({ isCheckedIn: true }, { merge: true })
      );
      await assertFails(ownerC.firestore().doc("orgs/org-c/events/evt-c/scheduleItems/item-1").set({ title: "Talk" }));
      await assertFails(ownerC.firestore().doc("orgs/org-c").set({ name: "New Name" }, { merge: true }));
    });

    // --- orgs/{orgId}.limits/status/plan are platform-controlled fields
    // — an org's own owner can update OTHER fields (name) but not these,
    // even though the general update rule would otherwise allow it. ---
    await check("org owner CAN rename their own org", async () => {
      await assertSucceeds(ownerA(testEnv).firestore().doc("orgs/org-a").set({ name: "Org A Renamed" }, { merge: true }));
    });

    await check("org owner CANNOT touch limits/status/plan directly — Admin-SDK (platform.ts) only", async () => {
      await assertFails(
        ownerA(testEnv).firestore().doc("orgs/org-a").set({ limits: { maxEvents: 9999 } }, { merge: true })
      );
      await assertFails(ownerA(testEnv).firestore().doc("orgs/org-a").set({ status: "active" }, { merge: true }));
      await assertFails(ownerA(testEnv).firestore().doc("orgs/org-a").set({ plan: "enterprise" }, { merge: true }));
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
