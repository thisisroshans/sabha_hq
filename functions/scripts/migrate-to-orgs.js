#!/usr/bin/env node
/**
 * One-off migration: bootstrap a single org from today's single-tenant
 * data, per docs/saas-schema.md (Phase 1 of the SaaS migration plan).
 *
 * What it does, in order:
 *   1. Creates orgs/{orgId} if it doesn't already exist.
 *   2. Lists every Firebase Auth user signed in with email/password (i.e.
 *      today's definition of "admin" — see firestore.rules' isAdmin()),
 *      makes each one a member of the org with role 'owner', AND sets
 *      their {orgId, role} custom claim directly (bypassing the invite
 *      flow in functions/src/invites.ts — there's no one to send THEM an
 *      invite). Skipping the claim would be a real lockout: task #5's
 *      rules check request.auth.token.orgId, and without this step the
 *      bootstrap owner would have a membership doc but no way to satisfy
 *      that check. Adjust roles by hand afterwards if 'owner' for
 *      everyone existing is too generous for your team.
 *   3. Copies every root-level events/{eventId} doc, and its attendees/
 *      and feedback/ subcollections, to orgs/{orgId}/events/{eventId}/...
 *      — SAME ids, so it's safe to re-run (uses set(), not add()).
 *      Attendee docs also get a denormalised orgId field written on (see
 *      docs/saas-schema.md for why that field exists).
 *
 * What it deliberately does NOT do:
 *   - Delete the original root-level events/*. This is a copy, not a move.
 *     The legacy tree stays in place as a rollback path until the app is
 *     actually cut over to reading orgs/{orgId}/... (a later, separate
 *     task) and the copy is confirmed correct. Cleaning up the legacy
 *     tree is a deliberate follow-up step, not a side effect of this
 *     script.
 *   - Set custom claims on any user. That's a separate Cloud Function
 *     (task #4 in the migration plan), triggered on invite-accept — this
 *     script only creates the Firestore membership doc it will read.
 *   - Touch production. See "Usage" below — it refuses to run against a
 *     non-emulator target unless you pass --execute AND --i-mean-it.
 *
 * Usage
 * -----
 *   Dry run against the emulator (default — always do this first):
 *     FIRESTORE_EMULATOR_HOST=localhost:8080 \
 *     FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
 *     GCLOUD_PROJECT=sabha-hq \
 *     node scripts/migrate-to-orgs.js
 *
 *   Actually write, against the emulator:
 *     ...same env vars... node scripts/migrate-to-orgs.js --execute
 *
 *   Against production (deliberately made awkward — this is a one-way
 *   door for real event data, don't run it casually):
 *     GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
 *     node scripts/migrate-to-orgs.js --execute --i-mean-it
 *
 *   Options:
 *     --org-id=<slug>      default: "unpuzzle"
 *     --org-name=<name>    default: "Unpuzzle"
 *     --execute            without this, nothing is written — report only
 *     --i-mean-it          required in addition to --execute when neither
 *                          FIRESTORE_EMULATOR_HOST nor
 *                          FIREBASE_AUTH_EMULATOR_HOST is set, i.e. when
 *                          this would hit a real project
 */

const admin = require("firebase-admin");
const { DEFAULT_LIMITS } = require("../lib/limits");

function parseArgs(argv) {
  const args = { orgId: "unpuzzle", orgName: "Unpuzzle", execute: false, iMeanIt: false };
  for (const raw of argv.slice(2)) {
    if (raw === "--execute") args.execute = true;
    else if (raw === "--i-mean-it") args.iMeanIt = true;
    else if (raw.startsWith("--org-id=")) args.orgId = raw.slice("--org-id=".length);
    else if (raw.startsWith("--org-name=")) args.orgName = raw.slice("--org-name=".length);
    else {
      console.error(`Unknown argument: ${raw}`);
      process.exit(1);
    }
  }
  return args;
}

function isEmulatorTarget() {
  return Boolean(process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST);
}

// Firestore batched writes cap at 500 operations; chunk to stay under it.
const BATCH_LIMIT = 400;

class BatchWriter {
  constructor(db, dryRun) {
    this.db = db;
    this.dryRun = dryRun;
    this.batch = db.batch();
    this.pending = 0;
    this.totalWrites = 0;
  }

  async set(ref, data) {
    this.totalWrites += 1;
    if (this.dryRun) return;
    this.batch.set(ref, data, { merge: true });
    this.pending += 1;
    if (this.pending >= BATCH_LIMIT) await this.flush();
  }

  async flush() {
    if (this.dryRun || this.pending === 0) return;
    await this.batch.commit();
    this.batch = this.db.batch();
    this.pending = 0;
  }
}

async function main() {
  const args = parseArgs(process.argv);
  const dryRun = !args.execute;
  const emulator = isEmulatorTarget();

  if (args.execute && !emulator && !args.iMeanIt) {
    console.error(
      "Refusing to write: no FIRESTORE_EMULATOR_HOST/FIREBASE_AUTH_EMULATOR_HOST set, " +
        "so --execute would hit a real project. Add --i-mean-it if that's truly what you want."
    );
    process.exit(1);
  }

  admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "sabha-hq" });
  const db = admin.firestore();
  const auth = admin.auth();

  console.log(`Target: ${emulator ? "EMULATOR" : "*** PRODUCTION ***"}`);
  console.log(`Mode:   ${dryRun ? "DRY RUN (no writes)" : "EXECUTE (writing)"}`);
  console.log(`Org:    ${args.orgId} ("${args.orgName}")`);
  console.log("");

  const writer = new BatchWriter(db, dryRun);
  const orgRef = db.collection("orgs").doc(args.orgId);

  // --- 1. Org doc ---------------------------------------------------
  const orgSnap = await orgRef.get();
  if (orgSnap.exists) {
    console.log(`orgs/${args.orgId} already exists — leaving its fields as-is.`);
  } else {
    await writer.set(orgRef, {
      name: args.orgName,
      status: "active",
      limits: DEFAULT_LIMITS,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`orgs/${args.orgId}: will create.`);
  }

  // --- 2. Members, from existing password-auth users -----------------
  // Mirrors firestore.rules' current isAdmin() = sign_in_provider == 'password'.
  let memberCount = 0;
  let nextPageToken;
  do {
    const page = await auth.listUsers(1000, nextPageToken);
    for (const user of page.users) {
      const isPasswordUser = user.providerData.some((p) => p.providerId === "password");
      if (!isPasswordUser) continue;
      memberCount += 1;
      await writer.set(orgRef.collection("members").doc(user.uid), {
        email: user.email || null,
        role: "owner",
        joinedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      if (!dryRun) {
        const existingClaims = user.customClaims || {};
        await auth.setCustomUserClaims(user.uid, { ...existingClaims, orgId: args.orgId, role: "owner" });
      }
    }
    nextPageToken = page.pageToken;
  } while (nextPageToken);
  console.log(`Members: ${memberCount} password-auth user(s) -> role 'owner' (Firestore doc + custom claim).`);

  // --- 3. Events + attendees + feedback ------------------------------
  const eventsSnap = await db.collection("events").get();
  let attendeeCount = 0;
  let feedbackCount = 0;

  for (const eventDoc of eventsSnap.docs) {
    const destEventRef = orgRef.collection("events").doc(eventDoc.id);
    await writer.set(destEventRef, eventDoc.data());

    const attendeesSnap = await eventDoc.ref.collection("attendees").get();
    for (const a of attendeesSnap.docs) {
      attendeeCount += 1;
      await writer.set(destEventRef.collection("attendees").doc(a.id), {
        ...a.data(),
        orgId: args.orgId, // denormalised, see docs/saas-schema.md
      });
    }

    const feedbackSnap = await eventDoc.ref.collection("feedback").get();
    for (const f of feedbackSnap.docs) {
      feedbackCount += 1;
      await writer.set(destEventRef.collection("feedback").doc(f.id), f.data());
    }
  }
  await writer.flush();

  console.log(`Events:    ${eventsSnap.size} -> orgs/${args.orgId}/events/*`);
  console.log(`Attendees: ${attendeeCount} (+ orgId field)`);
  console.log(`Feedback:  ${feedbackCount}`);
  console.log("");
  console.log(
    dryRun
      ? "Dry run only — nothing was written. Re-run with --execute to write."
      : `Done. Original root-level events/* left untouched — verify orgs/${args.orgId}/... before cleaning those up separately.`
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
