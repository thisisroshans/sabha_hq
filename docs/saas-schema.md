# Multi-tenant schema (SaaS migration, Phase 1)

Part of the [switch_to_saas] branch work. See the "Sabha HQ SaaS migration plan" memory for the
full phased plan this is one step of.

## Why path-based isolation, not a flat `orgId` field

The alternative — keep `events/{eventId}` flat, add an `orgId` field, filter every query by it — was
rejected. A forgotten `.where('orgId', ==, mine)` is a silent cross-tenant data leak, and the
pre-migration codebase already has exactly that shape of bug: `event_repository.dart` streams the
entire `events` collection with no owner filter at all, and `firestore.rules`'s `isGuestSession()`
lets any anonymous check-in session read every event's attendee list, not just its own event's. With
path-based isolation, a query for someone else's org isn't a missing filter — it's not expressible.

## Collections

```
orgs/{orgId}
  name: string
  createdAt: Timestamp

orgs/{orgId}/members/{uid}
  email: string
  role: 'owner' | 'admin' | 'staff'
  joinedAt: Timestamp

orgs/{orgId}/members/{uid}/devices/{fcmToken}   — check-in push notifications
  platform: 'android' | 'ios' | 'web'
  updatedAt: Timestamp
  — written by the member's own app (self-service only, see firestore.rules);
    read by functions/src/notifications.ts to push every check-in to owners/admins

orgs/{orgId}/events/{eventId}          — same Event model/fields as today, unchanged
orgs/{orgId}/events/{eventId}/attendees/{id}
  — same Attendee model, PLUS a new denormalised `orgId` field (see below)
orgs/{orgId}/events/{eventId}/feedback/{id}
  — same EventFeedback model, unchanged
```

`role` finally gives [AppUser](../lib/core/models/app_user.dart)'s existing-but-unused `role` field
a real purpose. `owner` vs `admin` distinction exists for Phase 2 billing/member-management; until
that lands, treat them as equivalent.

## The one deliberate exception: denormalised `orgId` on attendees

`admin_dashboard/application/live_feed_providers.dart`'s `liveActivityStreamProvider` runs a
`collectionGroup('attendees')` query for the admin's "All Events" feed. A collection-group query
spans every org's attendees by construction — the org path alone can't scope it. So attendee docs
carry a plain `orgId` field purely so that one query (and its Firestore rule, and its composite
index — see [firestore.indexes.json](../firestore.indexes.json)) can filter to the caller's own org.
The org path remains the source of truth and the primary isolation boundary; this field is a
concession to one query shape, not a parallel isolation mechanism — nothing else should key off it.

## Auth model

Replaces `firestore.rules`'s current `isAdmin() = sign_in_provider == 'password'` (any admin
account, full access to everything) with custom claims: `{ orgId, role }`, set server-side by a
Cloud Function on invite-accept (task #4 — requires Functions, hence Phase 0 before this). Rules
become `request.auth.token.orgId == resource path's orgId`, scoped per-org instead of global.

## Migration

[functions/scripts/migrate-to-orgs.js](../functions/scripts/migrate-to-orgs.js) — see that file's
header comment for usage. Bootstraps a single org (`unpuzzle` by default) from the current
single-tenant data: every existing password-auth user becomes a member of it, every root-level
`events/*` doc (and its `attendees`/`feedback` subcollections) is copied under
`orgs/{orgId}/events/*`.

Deliberately **copies, never deletes** the original root-level data — old docs are left in place as
a rollback path until the new structure is verified and the app is cut over to read from it (that
cutover is task #4/#5/#6, not this script). Deleting the legacy `events/*` tree is a separate,
explicit, later step once the org-scoped app is confirmed working.

**Not run against production by this migration step.** Validated against the Firestore + Auth
emulators only (see the script's own usage notes). Running it for real is a deliberate later action,
not a side effect of writing it.
