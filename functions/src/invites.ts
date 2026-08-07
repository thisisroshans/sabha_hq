import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import { orgLimits } from "./limits";

export type Role = "owner" | "admin" | "staff";
const VALID_ROLES: Role[] = ["owner", "admin", "staff"];
const INVITE_TTL_MS = 7 * 24 * 60 * 60 * 1000; // 7 days

function db() {
  return admin.firestore();
}

interface CreateInviteData {
  orgId: string;
  email: string;
  role: Role;
}

interface AcceptInviteData {
  orgId: string;
  token: string;
}

/**
 * Raw handlers are exported separately from their onCall() wrappers so the
 * smoke test (functions/scripts/_smoke-test-invites.js) can invoke this
 * actual business logic directly with a hand-built CallableRequest, instead
 * of standing up the full Functions emulator + client SDK just to exercise
 * it. onCall() itself is Google's code, not worth re-testing here.
 */

export async function createInviteHandler(
  request: CallableRequest<CreateInviteData>
): Promise<{ token: string; expiresAt: string }> {
  const auth = request.auth;
  if (!auth) throw new HttpsError("unauthenticated", "Sign in first.");

  const { orgId, email, role } = request.data ?? ({} as CreateInviteData);
  if (typeof orgId !== "string" || !orgId) {
    throw new HttpsError("invalid-argument", "orgId is required.");
  }
  if (typeof email !== "string" || !email.includes("@")) {
    throw new HttpsError("invalid-argument", "A valid email is required.");
  }
  if (!VALID_ROLES.includes(role)) {
    throw new HttpsError("invalid-argument", `role must be one of: ${VALID_ROLES.join(", ")}`);
  }

  // Custom claims (see acceptInviteHandler) are the source of truth for
  // "which org, what role" — a Firestore lookup of the caller's own
  // membership doc would work too, but would let a revoked-but-not-yet-
  // Firestore-updated member keep inviting people; the token is refreshed
  // on every sign-in/every hour, so this self-heals faster.
  const callerOrgId = auth.token.orgId as string | undefined;
  const callerRole = auth.token.role as Role | undefined;
  const isAuthorized = callerOrgId === orgId && (callerRole === "owner" || callerRole === "admin");
  if (!isAuthorized) {
    throw new HttpsError("permission-denied", "Only an owner or admin of this org can invite members.");
  }

  const orgSnap = await db().collection("orgs").doc(orgId).get();
  if (!orgSnap.exists) throw new HttpsError("not-found", "Org not found.");
  if (orgSnap.data()?.status === "suspended") {
    throw new HttpsError("failed-precondition", "This organization is currently suspended.");
  }

  // Fail fast at invite-creation time too, not just at accept — no point
  // handing someone a link that can only ever fail. Accept still has the
  // authoritative check below, since seats could fill up between now and
  // whenever this invite is actually redeemed.
  const memberCountSnap = await db().collection("orgs").doc(orgId).collection("members").count().get();
  const limits = orgLimits(orgSnap.data());
  if (memberCountSnap.data().count >= limits.maxTeamMembers) {
    throw new HttpsError(
      "resource-exhausted",
      `This organization has reached its team member limit (${limits.maxTeamMembers}).`
    );
  }

  const normalizedEmail = email.trim().toLowerCase();
  const token = crypto.randomBytes(24).toString("hex");
  const now = admin.firestore.Timestamp.now();
  const expiresAt = admin.firestore.Timestamp.fromMillis(now.toMillis() + INVITE_TTL_MS);

  await db().collection("orgs").doc(orgId).collection("invites").doc(token).set({
    email: normalizedEmail,
    role,
    status: "pending",
    invitedBy: auth.uid,
    createdAt: now,
    expiresAt,
  });

  // No transactional email exists yet (that's Phase 2) — whoever calls
  // this is responsible for getting the token/link to the invitee out of
  // band (Slack, WhatsApp, copy-paste) until that lands.
  return { token, expiresAt: expiresAt.toDate().toISOString() };
}

export async function acceptInviteHandler(
  request: CallableRequest<AcceptInviteData>
): Promise<{ orgId: string; role: Role }> {
  const auth = request.auth;
  if (!auth) throw new HttpsError("unauthenticated", "Sign in first, then accept your invite.");

  const { orgId, token } = request.data ?? ({} as AcceptInviteData);
  if (typeof orgId !== "string" || !orgId) {
    throw new HttpsError("invalid-argument", "orgId is required.");
  }
  if (typeof token !== "string" || !token) {
    throw new HttpsError("invalid-argument", "token is required.");
  }

  const inviteRef = db().collection("orgs").doc(orgId).collection("invites").doc(token);
  const inviteSnap = await inviteRef.get();
  if (!inviteSnap.exists) {
    throw new HttpsError("not-found", "This invite doesn't exist or was already used.");
  }

  const invite = inviteSnap.data() as {
    email: string;
    role: Role;
    status: string;
    expiresAt: admin.firestore.Timestamp;
  };

  if (invite.status !== "pending") {
    throw new HttpsError("failed-precondition", "This invite has already been used or was revoked.");
  }
  if (invite.expiresAt.toMillis() < Date.now()) {
    throw new HttpsError("failed-precondition", "This invite has expired.");
  }

  const callerEmail = (auth.token.email as string | undefined)?.toLowerCase();
  if (!callerEmail || callerEmail !== invite.email) {
    throw new HttpsError("permission-denied", "This invite was sent to a different email address.");
  }

  const orgSnap = await db().collection("orgs").doc(orgId).get();
  if (!orgSnap.exists) throw new HttpsError("not-found", "Org not found.");
  if (orgSnap.data()?.status === "suspended") {
    throw new HttpsError("failed-precondition", "This organization is currently suspended.");
  }

  // Authoritative seat check — createInviteHandler already checked this
  // once, but seats can fill up between an invite being created and it
  // actually being redeemed, so this is what actually protects the limit.
  const memberCountSnap = await db().collection("orgs").doc(orgId).collection("members").count().get();
  const limits = orgLimits(orgSnap.data());
  if (memberCountSnap.data().count >= limits.maxTeamMembers) {
    throw new HttpsError(
      "resource-exhausted",
      `This organization has reached its team member limit (${limits.maxTeamMembers}).`
    );
  }

  const role = invite.role;

  // Client-side caveat: custom claims only appear in request.auth.token
  // after the client forces an ID token refresh (getIdTokenResult(true) /
  // a fresh sign-in) — they are NOT visible on the token that was valid
  // when this call was made. The Flutter side calling this needs to
  // refresh immediately after a successful acceptInvite response.
  await admin.auth().setCustomUserClaims(auth.uid, { orgId, role });

  await db().collection("orgs").doc(orgId).collection("members").doc(auth.uid).set({
    email: callerEmail,
    role,
    joinedAt: admin.firestore.Timestamp.now(),
  });

  await inviteRef.set(
    { status: "accepted", acceptedBy: auth.uid, acceptedAt: admin.firestore.Timestamp.now() },
    { merge: true }
  );

  return { orgId, role };
}

export const createInvite = onCall(createInviteHandler);
export const acceptInvite = onCall(acceptInviteHandler);
