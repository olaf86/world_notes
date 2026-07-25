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
- `reports/{autoId}`: server-created user report events. A user can submit
  multiple reports for the same message, subject to a short server-side
  cooldown.

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

User reports are submitted through the `reportMessage` callable. Clients do not
write `reports` directly and cannot update message `reportCount` directly.
The server applies a short per-user cooldown before accepting another report.

`reportMessage` writes the report event and upserts
`moderationReviews/{placeId}_{messageId}` with:

- `reviewSources: arrayUnion("userReport")`
- `reportCount: increment(1)`
- `reportReasonsSummary: arrayUnion(reason)`
- `status: "open"`

When an administrator resolves the message through `adminReviewMessage`, open
reports for the same `placeId`/`messageId` are closed as `accepted` for
`sensitive`/`hidden` decisions or `rejected` for `allow` decisions.
