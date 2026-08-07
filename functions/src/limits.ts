/** Shared by orgs.ts, platform.ts, checkIn.ts, and events.ts — one
 * definition of what an org's limits look like and what a new org starts
 * with, rather than each write path guessing its own defaults. */
export interface OrgLimits {
  maxTeamMembers: number;
  maxEvents: number;
  maxAttendeesPerEvent: number;
  checkInRateLimitPerMinute: number;
}

// "Free" tier defaults — there's no real plan tiering yet (billing is
// deliberately deferred, see docs/saas-schema.md); every org starts here
// and a platform owner adjusts per-org from the platform dashboard.
// checkInRateLimitPerMinute matches the value that used to be hardcoded
// directly in checkIn.ts, so existing behavior doesn't change for anyone
// until a platform owner deliberately raises or lowers it.
export const DEFAULT_LIMITS: OrgLimits = {
  maxTeamMembers: 5,
  maxEvents: 3,
  maxAttendeesPerEvent: 250,
  checkInRateLimitPerMinute: 8,
};

/** Effective limits for an org — its own orgs/{orgId}.limits map merged
 * over the defaults, so a partially-set limits map (or none at all, for
 * orgs created before this feature existed) still resolves to sane
 * values instead of undefined. */
export function orgLimits(orgData: FirebaseFirestore.DocumentData | undefined): OrgLimits {
  return { ...DEFAULT_LIMITS, ...(orgData?.limits ?? {}) };
}
