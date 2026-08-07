import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { OrgLimits, orgLimits } from "./limits";

function db() {
  return admin.firestore();
}

/** platformRole is a claim structurally separate from any org's
 * {orgId, role} — see firestore.rules' PLATFORM DASHBOARD section for why
 * that separation matters. Only 'owner' exists today. */
function requirePlatformOwner(auth: CallableRequest["auth"]): asserts auth is NonNullable<CallableRequest["auth"]> {
  if (!auth) throw new HttpsError("unauthenticated", "Sign in first.");
  if (auth.token.platformRole !== "owner") {
    throw new HttpsError("permission-denied", "Platform owner access required.");
  }
}

async function logPlatformAction(
  uid: string,
  action: string,
  orgId: string | null,
  details: Record<string, unknown>
): Promise<void> {
  await db()
    .collection("platformAuditLog")
    .add({
      uid,
      action,
      orgId,
      details,
      at: admin.firestore.FieldValue.serverTimestamp(),
    });
}

interface OrgSummary {
  id: string;
  name: string;
  plan: string;
  status: string;
  limits: OrgLimits;
  usage: {
    eventCount: number;
    teamMemberCount: number;
    attendeeCount: number;
  };
  createdAt: string | null;
}

function serializeOrg(id: string, data: FirebaseFirestore.DocumentData): Omit<OrgSummary, "usage"> {
  const createdAt = data.createdAt as admin.firestore.Timestamp | undefined;
  return {
    id,
    name: data.name ?? "(unnamed)",
    plan: data.plan ?? "free",
    status: data.status ?? "active",
    limits: orgLimits(data),
    createdAt: createdAt ? createdAt.toDate().toISOString() : null,
  };
}

/** Live usage via Firestore's count() aggregation queries rather than
 * trigger-maintained counters — a count() query is billed as a single
 * read regardless of collection size, so there's no need to maintain
 * denormalised counters (and no risk of them drifting out of sync with
 * reality if a trigger ever fails). attendeeCount uses the collectionGroup
 * + orgId filter (see firestore.indexes.json's fieldOverride) rather than
 * summing per-event counts, since attendees already carry a denormalised
 * orgId field for exactly this kind of cross-event query. */
async function usageForOrg(orgId: string) {
  const [eventCountSnap, memberCountSnap, attendeeCountSnap] = await Promise.all([
    db().collection("orgs").doc(orgId).collection("events").count().get(),
    db().collection("orgs").doc(orgId).collection("members").count().get(),
    db().collectionGroup("attendees").where("orgId", "==", orgId).count().get(),
  ]);

  return {
    eventCount: eventCountSnap.data().count,
    teamMemberCount: memberCountSnap.data().count,
    attendeeCount: attendeeCountSnap.data().count,
  };
}

/** Every org, with live usage — the org directory screen. */
export async function getPlatformOverviewHandler(
  request: CallableRequest<void>
): Promise<{ orgs: OrgSummary[] }> {
  requirePlatformOwner(request.auth);

  const orgsSnap = await db().collection("orgs").get();
  const orgs = await Promise.all(
    orgsSnap.docs.map(async (doc) => {
      const usage = await usageForOrg(doc.id);
      return { ...serializeOrg(doc.id, doc.data()), usage };
    })
  );

  return { orgs };
}

interface OrgDetailData {
  orgId: string;
}

/** One org, with live usage — the org detail screen. Separate from
 * getPlatformOverview rather than having the detail screen filter the
 * full list client-side, since usage is computed per-org anyway and
 * there's no reason to pay for every other org's count() queries just to
 * look at one. */
export async function getOrgDetailHandler(
  request: CallableRequest<OrgDetailData>
): Promise<OrgSummary> {
  requirePlatformOwner(request.auth);

  const orgId = request.data?.orgId;
  if (typeof orgId !== "string" || !orgId) {
    throw new HttpsError("invalid-argument", "orgId is required.");
  }

  const orgSnap = await db().collection("orgs").doc(orgId).get();
  if (!orgSnap.exists) throw new HttpsError("not-found", "Org not found.");

  const usage = await usageForOrg(orgId);
  return { ...serializeOrg(orgId, orgSnap.data()!), usage };
}

interface UpdateOrgLimitsData {
  orgId: string;
  limits: Partial<OrgLimits>;
}

const POSITIVE_INT_FIELDS: (keyof OrgLimits)[] = [
  "maxTeamMembers",
  "maxEvents",
  "maxAttendeesPerEvent",
  "checkInRateLimitPerMinute",
];

/** Updates one or more limit fields for an org. Partial — only the
 * fields present in the request change, the rest keep their current
 * (or default) value; this is what lets the dashboard's "edit one field"
 * UI not have to resend every limit every time. */
export async function updateOrgLimitsHandler(
  request: CallableRequest<UpdateOrgLimitsData>
): Promise<{ limits: OrgLimits }> {
  requirePlatformOwner(request.auth);

  const orgId = request.data?.orgId;
  const patch = request.data?.limits;
  if (typeof orgId !== "string" || !orgId) {
    throw new HttpsError("invalid-argument", "orgId is required.");
  }
  if (!patch || typeof patch !== "object" || Array.isArray(patch)) {
    throw new HttpsError("invalid-argument", "limits must be an object.");
  }

  const orgRef = db().collection("orgs").doc(orgId);
  const orgSnap = await orgRef.get();
  if (!orgSnap.exists) throw new HttpsError("not-found", "Org not found.");

  const updates: Record<string, number> = {};
  for (const field of POSITIVE_INT_FIELDS) {
    const value = patch[field];
    if (value === undefined) continue;
    if (typeof value !== "number" || !Number.isInteger(value) || value < 1) {
      throw new HttpsError("invalid-argument", `${field} must be a positive integer.`);
    }
    updates[`limits.${field}`] = value;
  }

  if (Object.keys(updates).length === 0) {
    throw new HttpsError("invalid-argument", "No valid limit fields provided.");
  }

  await orgRef.update(updates);

  const before = orgLimits(orgSnap.data());
  const after = orgLimits({ limits: { ...before, ...patch } });
  await logPlatformAction(request.auth!.uid, "update_limits", orgId, { before, after });

  return { limits: after };
}

interface SetOrgStatusData {
  orgId: string;
  status: "active" | "suspended";
}

/** Suspends or reactivates an org. Suspension blocks writes across the
 * org (firestore.rules' orgIsActive(), plus the same check added to
 * checkIn.ts/events.ts's callables) but deliberately leaves reads open —
 * see firestore.rules' PLATFORM DASHBOARD comment for why (so the org's
 * own admin UI can show a clear "you're suspended" state instead of a
 * wall of permission-denied errors). */
export async function setOrgStatusHandler(
  request: CallableRequest<SetOrgStatusData>
): Promise<{ status: string }> {
  requirePlatformOwner(request.auth);

  const orgId = request.data?.orgId;
  const status = request.data?.status;
  if (typeof orgId !== "string" || !orgId) {
    throw new HttpsError("invalid-argument", "orgId is required.");
  }
  if (status !== "active" && status !== "suspended") {
    throw new HttpsError("invalid-argument", "status must be 'active' or 'suspended'.");
  }

  const orgRef = db().collection("orgs").doc(orgId);
  const orgSnap = await orgRef.get();
  if (!orgSnap.exists) throw new HttpsError("not-found", "Org not found.");

  const before = orgSnap.data()?.status ?? "active";
  await orgRef.update({ status });
  await logPlatformAction(request.auth!.uid, "set_status", orgId, { before, after: status });

  return { status };
}

interface AuditLogData {
  orgId?: string;
  limit?: number;
}

interface AuditLogEntry {
  id: string;
  uid: string;
  action: string;
  orgId: string | null;
  details: Record<string, unknown>;
  at: string | null;
}

/** The platform audit log, optionally filtered to one org. */
export async function getPlatformAuditLogHandler(
  request: CallableRequest<AuditLogData>
): Promise<{ entries: AuditLogEntry[] }> {
  requirePlatformOwner(request.auth);

  const limit = Math.min(request.data?.limit ?? 50, 200);
  let query: FirebaseFirestore.Query = db().collection("platformAuditLog");
  if (request.data?.orgId) {
    query = query.where("orgId", "==", request.data.orgId);
  }
  const snap = await query.orderBy("at", "desc").limit(limit).get();

  const entries = snap.docs.map((doc) => {
    const data = doc.data();
    const at = data.at as admin.firestore.Timestamp | undefined;
    return {
      id: doc.id,
      uid: data.uid,
      action: data.action,
      orgId: data.orgId ?? null,
      details: data.details ?? {},
      at: at ? at.toDate().toISOString() : null,
    };
  });

  return { entries };
}

export const getPlatformOverview = onCall(getPlatformOverviewHandler);
export const getOrgDetail = onCall(getOrgDetailHandler);
export const updateOrgLimits = onCall(updateOrgLimitsHandler);
export const setOrgStatus = onCall(setOrgStatusHandler);
export const getPlatformAuditLog = onCall(getPlatformAuditLogHandler);
