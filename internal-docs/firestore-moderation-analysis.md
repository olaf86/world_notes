# Firestore moderation and notices model

## Firestore instance

- Project: `world-notes-prod`
- Database: `(default)`
- Edition: `STANDARD`
- Type: `FIRESTORE_NATIVE`

## Existing paths touched by this work

- `users/{uid}`: owner-only profile document. Contains PII fields such as
  `email`; reads must remain owner-only.
- `users/{uid}/fcmTokens/{tokenId}`: server-only token store used by Cloud
  Functions for FCM delivery.
- `users/{uid}/notificationSettings/main`: owner-readable, server-writable.
- `places/{placeId}` and `places/{placeId}/messages/{messageId}`: messages are
  read only by users who can access the parent note. Messages can carry
  `moderationAction: "pending"` when provider-side moderation is temporarily
  unavailable; pending messages remain visible and should be re-evaluated by a
  future scheduled function.
- `reports/{placeId}_{messageId}_{reporterId}`: server-created user report
  events. The document id makes repeat reports by the same user for the same
  message idempotent.

## New path

- `moderationReviews/{placeId}_{messageId}`: flat administrator review queue
  for non-allow moderation decisions and high-confidence app risk signals such
  as contact information. Stores `userId`, `placeId`, `messageId`, submitted
  content, optional submitted image storage path, provider scores, derived
  action, review sources, risk signals, report count/summary, and review
  status. Client access is denied; administrator tooling should use trusted
  server APIs.
- `moderationAuditLogs/{logId}`: server-only append log for administrator
  moderation decisions. Stores the administrator uid, reviewed message path,
  action, reason, previous moderation fields, and timestamp.
- `users/{uid}/notices/{noticeId}`: app inbox items for moderation warnings,
  account restrictions, bans, report outcomes, and future developer messages.
  Owner may read and mark read. Creation, deletion, and content changes are
  server-only.

## Queries added

- `users/{uid}/notices.orderBy(createdAt desc).limit(100)`

This is a single-collection query scoped under the signed-in user, so no
composite index is expected.

Future administrator tooling can query `moderationReviews` by `status`,
`createdAt`, `userId`, `placeId`, or `action`. The initial administrator queue
uses `status == "open"` ordered by `createdAt`; the Flutter administrator
screen reads open/resolved queues through `adminListModerationReviews`, not
direct Firestore client reads.

Future delayed moderation tooling can use a collection group query over
`messages` where `moderationAction == "pending"`. Add the required index when
that scheduled function is implemented.

## Rule requirement

- Require auth.
- Allow only the owner to read their notices.
- Allow only owner updates to `readAt`, because notice text/severity/action are
  authoritative server content.
- Deny client create/delete.
- Deny all client access to `moderationReviews`.
- Deny all client access to `moderationAuditLogs`.

## Administrator access

Moderation administrator access is controlled by Firebase Auth custom claims.
The callables `adminListModerationReviews` and `adminReviewMessage` require
`admin: true`; hiding the Flutter UI is only a convenience, not the
authorization boundary.

The Flutter profile screen only links to `/admin/moderation` when the current
ID token contains `admin: true`. The screen still calls the same trusted
callables, so direct route access by a normal user fails at the backend.

Set or remove the claim from `functions/`:

```bash
npm run admin:set -- --email admin@example.com
npm run admin:unset -- --email admin@example.com
```

The target user must refresh their ID token or sign in again after the claim
changes.

## User report flow

User reports are submitted through the `reportMessage` callable. Clients do not
write `reports` directly and cannot update message `reportCount` directly.

`reportMessage` writes the report event and upserts
`moderationReviews/{placeId}_{messageId}` with:

- `reviewSources: arrayUnion("userReport")`
- `reportCount: increment(1)`
- `reportReasonsSummary: arrayUnion(reason)`
- `status: "open"`

When an administrator resolves the message through `adminReviewMessage`, open
reports for the same `placeId`/`messageId` are closed as `accepted` for
`sensitive`/`hidden` decisions or `rejected` for `allow` decisions.
