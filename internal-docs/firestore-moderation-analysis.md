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
  read only by users who can access the parent note. Notes carry
  `isModerationHidden` so moderation can remove them from discovery and public
  reads without changing their archive lifecycle. Messages can carry
  `moderationAction: "pending"` when provider-side moderation is temporarily
  unavailable; pending messages remain visible and should be re-evaluated by a
  future scheduled function.
- `reports/{autoId}`: server-created note or message report events. Reports use
  `targetType`, `targetId`, `targetPath`, and a locale-independent
  `reasonCode`. A shared per-user cooldown covers both target types.

## New path

- `moderationReviews/{reviewId}`: flat administrator review queue for notes and
  messages. Message reviews use `{placeId}_{messageId}` and note reviews use
  `note_{placeId}` as deterministic document ids. Every record identifies its
  content exclusively through `targetType`, `targetId`, and `targetPath`; the
  target-specific `messageId` and `messagePath` fields are not stored. The
  review stores submitted content, optional image storage paths, provider
  scores, derived action, review sources, risk signals, report count/summary,
  and review status.
- `moderationAuditLogs/{logId}`: server-only append log for both automated
  rejections and administrator decisions. `eventType` distinguishes
  `automatedRejection` from `adminDecision`, and `actorType` distinguishes the
  moderation provider from an administrator. Automated entries retain
  provider metadata, the affected user, source type, and post-decision
  violation-point total. Administrator entries retain the affected target,
  affected user, reason, and previous moderation state. The collection never
  stores submitted text or image bytes and is not an administrator review
  queue.
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
The callables `adminListModerationReviews`, `adminReviewMessage`, and
`adminReviewNote` require `admin: true`; hiding the Flutter UI is only a
convenience, not the authorization boundary.

The Flutter profile screen only links to `/admin/moderation` when the current
ID token contains `admin: true`. The screen still calls the same trusted
callables, so direct route access by a normal user fails at the backend.

### Grant or remove access

Run these commands from `functions/`. Install the Node.js dependencies first
when this is a new checkout:

```bash
cd functions
npm ci
```

The default Firebase project is `world-notes-prod`, as configured in
`.firebaserc`. To target another project, prepend the command with
`GCLOUD_PROJECT=<project-id>`.

The script uses Application Default Credentials (ADC). When local user ADC
does not have a quota project, run the script with a command-scoped quota
project instead of changing the saved ADC configuration:

```bash
GOOGLE_CLOUD_QUOTA_PROJECT=world-notes-prod \
  npm run admin:set -- --email admin@example.com
```

This environment variable applies only to that command. The executing Google
account needs permission to administer Firebase Auth users and the Service
Usage Consumer role (`roles/serviceusage.serviceUsageConsumer`) on the quota
project.

To grant or remove the claim by UID instead of email, replace `--email` with
`--uid`:

```bash
npm run admin:set -- --email admin@example.com
npm run admin:unset -- --email admin@example.com
```

The target user must refresh their ID token or sign in again after the claim
changes. After that, the **Moderation** item appears on the profile screen.

### Check local ADC quota-project configuration

The saved quota project in local user ADC can be inspected with:

```bash
jq -r '.quota_project_id // "(not set)"' \
  ~/.config/gcloud/application_default_credentials.json
```

This is separate from the default project in `gcloud config`. If
`GOOGLE_APPLICATION_CREDENTIALS` is set, ADC uses that credential file before
the local file above; inspect it first with:

```bash
echo "${GOOGLE_APPLICATION_CREDENTIALS:-'(not set)'}"
```

## Moderation evaluation

The version-controlled evaluation set lives at
`functions/evaluation/moderation-cases.json`. Each case has a human-labelled
`expectedAction` (`allow`, `sensitive`, `review`, or `hidden`) and expected
app-level contact-information risk signals. The set covers ordinary diary
entries, contextual safety discussion, contact details, and unsafe content.

Run it from `functions/` only after a reviewer has checked the case labels.
The evaluator calls the live OpenAI Moderation API sequentially; it does not
use Firebase secrets, deploy Cloud Functions, create Firestore data, or print
the test message contents.

```bash
cd functions
read -rs OPENAI_API_KEY
export OPENAI_API_KEY
npm run evaluate:moderation -- --json /private/tmp/world-notes-moderation.json
unset OPENAI_API_KEY
```

The terminal table and optional JSON report contain only case IDs, expected and
actual actions, risk signals, scores, and matched categories. The JSON also
records the provider model and policy version, so reports remain comparable
after a model or policy update. It calculates action accuracy, risk-signal
accuracy, review-queue accuracy, false allows, unexpected moderation, and
review-queue misses.

Use `--fail-on-mismatch` in a controlled validation run to return a nonzero
exit status when any expected action, risk signal, or review-queue result does
not match:

```bash
npm run evaluate:moderation -- --fail-on-mismatch
```

Treat a mismatch as a review task, not an automatic policy change. Review the
case text and the model result, then update either the human label or the
moderation thresholds with an explicit policy decision. Do not commit API keys
or generated reports containing production data.

## User report flow

User reports are submitted through the `reportMessage` and `reportNote`
callables. Clients do not write `reports` directly. The server applies one
short per-user cooldown across both callables.

`reportMessage` writes the report event and upserts
`moderationReviews/{placeId}_{messageId}` with:

- `reviewSources: arrayUnion("userReport")`
- `reportCount: increment(1)`
- `reportReasonsSummary: arrayUnion(reasonCode)`
- `status: "open"`

When an administrator resolves the message through `adminReviewMessage`, open
reports for the same `targetType`/`targetId` are closed as `accepted` for
`sensitive`/`hidden` decisions or `rejected` for `allow` decisions.

`reportNote` upserts `moderationReviews/note_{placeId}` with the same report
summary fields plus a title/subtitle snapshot and the current pin image path.
`adminReviewNote` either allows the note or sets `isModerationHidden: true`.
Hidden notes are rejected by public Firestore reads, map discovery, note access
validation, message posting, likes, visits, unlocks, and invite claims.

## Publication-time checks

- `createNote` and `sendMessage` atomically attach immutable-input-bound
  moderation jobs and return while their content is `pending`.
- `setNotePinImage` verifies immutable Storage object metadata, attaches a
  separate `pinImageCandidate`, and queues regional image evaluation without
  waiting for the provider.
- Map/detail reads prefer the pending pin candidate, while
  `pinImageStoragePath` retains the last accepted image. An `allow` result
  promotes the candidate and durably deletes the previous image. Any other
  completed result removes and durably deletes only the candidate.
- Regional upload tracking and generation-guarded cleanup own failed,
  superseded, rejected, and orphaned image removal.
- A message that remains moderation-hidden for 30 days enters a durable purge
  workflow. The worker first closes administrator restoration, deletes its
  like edges in bounded batches, queues every referenced image for guarded
  Storage deletion, deletes the raw-content review record, and deletes the
  message.
- Post-purge evidence contains moderation and lifecycle metadata only. It does
  not retain raw content, image paths, or a content-derived digest. The
  evidence expires after one year through the existing
  `moderationAuditLogs.expireAt` TTL policy.
