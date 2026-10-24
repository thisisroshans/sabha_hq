#!/usr/bin/env node
/**
 * Mock data for the end-to-end test (integration_test/e2e_test.dart) —
 * EMULATOR ONLY. Wipes the local Auth + Firestore emulators and seeds one
 * org, one owner account, one event with an agenda, and a mix of Movers
 * and Pitchers (stored roles 'guest'/'participant' — see AttendeeRole in
 * lib/core/models/attendee.dart), some already checked in.
 *
 * Usage (with `firebase emulators:start --only auth,firestore,functions
 * --project sabha-hq` running):
 *
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
 *   FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
 *   GCLOUD_PROJECT=sabha-hq node scripts/seed-e2e-emulator.js
 *
 * The org id, event id and owner login come from
 * integration_test/e2e_fixture.json — the same file the test reads via
 * --dart-define-from-file, so the two can't drift apart. The password in
 * it is a throwaway generated for the emulator; it exists nowhere else.
 */

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const LOCAL_HOST = /^(localhost|127\.0\.0\.1|\[::1\]):\d+$/;

function requireEmulator(name) {
  const value = process.env[name];
  if (!value || !LOCAL_HOST.test(value)) {
    throw new Error(`Refusing to run: ${name} must point at a local emulator (got ${value || "nothing"}).`);
  }
  return value;
}

async function wipe(url) {
  const res = await fetch(url, { method: "DELETE" });
  if (!res.ok) throw new Error(`Emulator wipe failed (${res.status}): ${url}`);
}

const minutesAgo = (m) => admin.firestore.Timestamp.fromDate(new Date(Date.now() - m * 60_000));
const minutesFromNow = (m) => admin.firestore.Timestamp.fromDate(new Date(Date.now() + m * 60_000));

async function main() {
  const firestoreHost = requireEmulator("FIRESTORE_EMULATOR_HOST");
  const authHost = requireEmulator("FIREBASE_AUTH_EMULATOR_HOST");
  const projectId = process.env.GCLOUD_PROJECT || "sabha-hq";

  const fixture = JSON.parse(
    fs.readFileSync(path.join(__dirname, "..", "..", "integration_test", "e2e_fixture.json"), "utf8")
  );
  const orgId = fixture.E2E_ORG_ID;
  const eventId = fixture.E2E_EVENT_ID;

  // Start from nothing, so every run of the test sees the same data.
  await wipe(`http://${firestoreHost}/emulator/v1/projects/${projectId}/databases/(default)/documents`);
  await wipe(`http://${authHost}/emulator/v1/projects/${projectId}/accounts`);

  admin.initializeApp({ projectId });
  const db = admin.firestore();

  const owner = await admin.auth().createUser({
    email: fixture.E2E_OWNER_EMAIL,
    password: fixture.E2E_OWNER_PASSWORD,
    emailVerified: true,
  });
  await admin.auth().setCustomUserClaims(owner.uid, { orgId, role: "owner" });

  await db.doc(`orgs/${orgId}`).set({
    name: "Demo Ventures",
    status: "active",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await db.doc(`orgs/${orgId}/members/${owner.uid}`).set({
    email: fixture.E2E_OWNER_EMAIL,
    role: "owner",
    joinedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const eventRef = db.doc(`orgs/${orgId}/events/${eventId}`);
  await eventRef.set({
    title: "Demo Day 2026",
    location: "Bengaluru",
    date: admin.firestore.Timestamp.fromDate(new Date()),
    branding: { primaryColor: "#c51f43" },
  });

  const agenda = [
    { title: "Welcome & opening remarks", start: -30, end: 15, speaker: "Host" },
    { title: "Pitch session 1", start: 15, end: 75, speaker: "Pitchers" },
    { title: "Networking lunch", start: 75, end: 135 },
  ];
  for (const [i, item] of agenda.entries()) {
    await eventRef.collection("scheduleItems").doc(`item-${i + 1}`).set({
      eventId,
      title: item.title,
      startTime: minutesFromNow(item.start),
      endTime: minutesFromNow(item.end),
      ...(item.speaker ? { speaker: item.speaker } : {}),
    });
  }

  // role: 'guest' = Mover, 'participant' = Pitcher. checkedInMinutesAgo
  // null = registered but not checked in yet (the test checks some of
  // these in, at the kiosk and from the dashboard).
  const attendees = [
    { id: "ravi", name: "Ravi Kumar", phone: "9876500001", role: "guest", checkedInMinutesAgo: null },
    { id: "ananya", name: "Ananya Iyer", phone: "9876500002", role: "guest", company: "Northwind", checkedInMinutesAgo: 42 },
    { id: "karan", name: "Karan Mehta", phone: "9876500003", role: "guest", checkedInMinutesAgo: null },
    { id: "meera", name: "Meera Nair", phone: "9876500004", role: "guest", checkedInMinutesAgo: 25 },
    {
      id: "asha", name: "Asha Rao", phone: "9876500011", role: "participant",
      company: "Acme Robotics", designation: "Founder", industry: "Robotics", checkedInMinutesAgo: 38,
    },
    {
      id: "vikram", name: "Vikram Shah", phone: "9876500012", role: "participant",
      company: "Ledgerly", designation: "CEO", industry: "Fintech", checkedInMinutesAgo: null,
    },
    {
      id: "neha", name: "Neha Gupta", phone: "9876500013", role: "participant",
      company: "GreenGrid", designation: "Co-founder", industry: "Climate", checkedInMinutesAgo: 12,
    },
  ];
  for (const a of attendees) {
    await eventRef.collection("attendees").doc(a.id).set({
      eventId,
      orgId,
      name: a.name,
      phone: a.phone,
      email: `${a.id}@example.test`,
      role: a.role,
      companyName: a.company ?? "",
      designation: a.designation ?? "",
      industry: a.industry ?? "",
      isCheckedIn: a.checkedInMinutesAgo !== null,
      checkInTime: a.checkedInMinutesAgo !== null ? minutesAgo(a.checkedInMinutesAgo) : null,
    });
  }

  const movers = attendees.filter((a) => a.role === "guest").length;
  console.log(
    `Seeded org "${orgId}", event "${eventId}", owner ${fixture.E2E_OWNER_EMAIL}, ` +
      `${movers} Movers + ${attendees.length - movers} Pitchers.`
  );
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("SEED FAILED:", err);
    process.exit(1);
  });
