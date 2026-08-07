#!/usr/bin/env node
/**
 * Grants (or revokes) the platformRole custom claim on a Sabha HQ staff
 * account — a claim structurally separate from any org's {orgId, role},
 * see firestore.rules' PLATFORM DASHBOARD section for why that separation
 * matters. There's no UI to do this (deliberately — this is Sabha HQ's own
 * team, not something an org, or even another platform-staff account,
 * should be able to self-serve), so it's a script, same pattern as
 * migrate-to-orgs.js's bootstrap owner.
 *
 * Usage
 * -----
 *   Dry run against the emulator (default — always do this first):
 *     FIRESTORE_EMULATOR_HOST=localhost:8080 \
 *     FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
 *     GCLOUD_PROJECT=sabha-hq \
 *     node scripts/grant-platform-staff.js --email=you@sabha.example --role=owner
 *
 *   Actually write, against the emulator:
 *     ...same env vars... node scripts/grant-platform-staff.js --email=... --role=owner --execute
 *
 *   Against production (deliberately awkward — this grants visibility
 *   into every customer's data, don't run it casually):
 *     GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
 *     node scripts/grant-platform-staff.js --email=... --role=owner --execute --i-mean-it
 *
 *   Revoke:
 *     node scripts/grant-platform-staff.js --email=... --revoke --execute --i-mean-it
 *
 *   Options:
 *     --email=<email>   required — must already be a Firebase Auth user
 *                        (create the account first, e.g. via signup)
 *     --role=owner       platformRole to grant (only 'owner' exists today)
 *     --revoke           remove platformRole instead of granting it
 *     --execute          without this, nothing is written — report only
 *     --i-mean-it        required in addition to --execute when neither
 *                        FIRESTORE_EMULATOR_HOST nor
 *                        FIREBASE_AUTH_EMULATOR_HOST is set
 */

const admin = require("firebase-admin");

function parseArgs(argv) {
  const args = { email: null, role: "owner", revoke: false, execute: false, iMeanIt: false };
  for (const raw of argv.slice(2)) {
    if (raw === "--execute") args.execute = true;
    else if (raw === "--i-mean-it") args.iMeanIt = true;
    else if (raw === "--revoke") args.revoke = true;
    else if (raw.startsWith("--email=")) args.email = raw.slice("--email=".length);
    else if (raw.startsWith("--role=")) args.role = raw.slice("--role=".length);
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

async function main() {
  const args = parseArgs(process.argv);
  if (!args.email) {
    console.error("Usage: node scripts/grant-platform-staff.js --email=<email> [--role=owner] [--revoke] [--execute] [--i-mean-it]");
    process.exit(1);
  }
  if (!args.revoke && args.role !== "owner") {
    console.error(`Unknown role '${args.role}' — only 'owner' exists today.`);
    process.exit(1);
  }

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
  const auth = admin.auth();

  console.log(`Target: ${emulator ? "EMULATOR" : "*** PRODUCTION ***"}`);
  console.log(`Mode:   ${dryRun ? "DRY RUN (no writes)" : "EXECUTE (writing)"}`);
  console.log(`Action: ${args.revoke ? "REVOKE" : `GRANT platformRole='${args.role}'`} for ${args.email}`);
  console.log("");

  const user = await auth.getUserByEmail(args.email).catch(() => null);
  if (!user) {
    console.error(`No Firebase Auth user found for ${args.email} — create the account first (e.g. via /signup).`);
    process.exit(1);
  }

  const existingClaims = user.customClaims || {};
  if (existingClaims.orgId) {
    console.log(
      `Note: this account also has an org claim (orgId=${existingClaims.orgId}, role=${existingClaims.role}). ` +
        "Both claims coexist fine — platformRole is checked independently in rules — but worth knowing " +
        "this isn't a dedicated platform-only account."
    );
  }

  const newClaims = { ...existingClaims };
  if (args.revoke) {
    delete newClaims.platformRole;
  } else {
    newClaims.platformRole = args.role;
  }

  if (dryRun) {
    console.log(`Would set custom claims to: ${JSON.stringify(newClaims)}`);
    console.log("\nDry run only — nothing was written. Re-run with --execute to write.");
    return;
  }

  await auth.setCustomUserClaims(user.uid, newClaims);
  console.log(`Done. ${user.email} (${user.uid}) now has claims: ${JSON.stringify(newClaims)}`);
  console.log(
    "\nThat account's client must force an ID token refresh (or sign out/in) before " +
      "the new claim is visible to it — same caveat as every other claim change in this app."
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
