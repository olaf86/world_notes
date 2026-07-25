# App submission content-safety additions

## Implementation status

Implemented on `codex/app-submission-content-safety`:

- locale-independent report reason codes and a generic target schema;
- Japanese and all release-locale report UI copy;
- note reporting from the note detail screen;
- note and message targets in the administrator review queue;
- fail-closed title/subtitle moderation in `createNote`;
- message-image and pin-thumbnail moderation before Firestore publication;
- candidate image cleanup on rejection and callable failure;
- moderation-hidden note enforcement across discovery, reads, posting, likes,
  visits, unlocks, and invite claims;
- unit/widget coverage for reason codes, multimodal result aggregation,
  localization, note visibility, review parsing, and the report UI.

Deployment still requires the existing `OPENAI_API_KEY` secret, the updated
Functions, Firestore rules, and the new reports composite index to be deployed
together.

## Decision

Implement the following four submission-readiness items together:

1. Reporting a note itself
2. Moderating a note title and description before publication
3. Moderating uploaded message and map-pin images
4. Localizing the user-report flow

User blocking should be a separate change set. It introduces a new relationship
model and affects map discovery, message lists, profiles, and interaction
permissions, while the four items above can share the existing report and
moderation pipeline.

Land the content-safety change first, then branch the blocking work from the
updated main branch. This reduces conflicts in the note and message action
menus.

## Current implementation

- `sendMessage` moderates message text with
  `omni-moderation-latest` before writing the message.
- Non-allow message decisions and risk signals can create a flat
  `moderationReviews` item.
- `reportMessage` creates a server-owned `reports` event, updates the review
  item, applies a per-user cooldown, and prevents self-reporting.
- `adminReviewMessage` resolves message reviews and matching open reports.
- Message and pin images are uploaded to Firebase Storage before their
  respective callable is invoked. The callables validate the expected path,
  type, and size, but do not inspect the image content.
- The report screen, related message actions, success message, errors, and
  report reasons are hardcoded in English.
- Report reasons are currently stored as their English display labels rather
  than stable reason codes.
- The moderation review schema and administrator action are message-specific.

## Shared schema changes

Use stable target and reason values so stored moderation data is independent of
the app locale.

Suggested report fields:

```text
targetType: "message" | "note"
targetId: string
targetPath: string
placeId: string
reporterId: string
reportedUserId: string
reasonCode: "spam" | "harassment" | "sexual" | "illegal" | "other"
status: "open" | "accepted" | "rejected"
createdAt: timestamp
```

Suggested additions to `moderationReviews`:

```text
targetType: "message" | "note"
targetId: string
targetPath: string
contentFields: map       # e.g. message text or note title/subtitle
imageStoragePaths: string[]
```

Keep reading and writing both collections server-only. Migrate existing
documents before deploying the code that requires these fields; do not retain
target-specific aliases in the application schema.

Prefer a generic `adminReviewContent` callable over adding more branching to
`adminReviewMessage`. Message and note decisions have different side effects,
but can share authentication, input validation, audit logging, report
resolution, and image cleanup.

## 1. Report a note

### Backend

- Add a `reportNote` callable, or a generic `reportContent` callable with a
  strict target-type validator.
- Verify that the note exists, is reportable by the caller, and was not created
  by the caller.
- Store a canonical reason code, not localized display text.
- Apply a server-side cooldown. A shared report cooldown is preferable to
  independent note and message cooldowns so alternating target types cannot
  bypass throttling.
- Snapshot the note title, subtitle, creator, and current pin image path into
  the moderation review.
- Extend administrator resolution to note targets.
- When an administrator hides a reported note, set a moderation visibility
  field instead of archiving it. Archiving changes lifecycle and active-note
  capacity and is not reversible in the current model.
- Exclude moderation-hidden notes from `listMapPins`, public direct reads, note
  access validation, notifications, likes, visits, and new message posting.
  The creator may retain a read-only view through My Notes and receive a
  moderation notice.

### Flutter

- Add a report action to a note that the current user does not maintain.
- Keep it easily reachable from the note detail screen. A map-preview shortcut
  is optional because detail-screen access is sufficient for the first release.
- Reuse one report screen whose title and explanation vary by target type.
- Add success, failure, cooldown, already-unavailable, and self-report messages.

### Tests

- Callable validation, self-report denial, inaccessible-note denial, cooldown,
  report/review writes, retry behavior, and concurrent reports.
- Administrator allow/hide actions and matching report resolution.
- Map and direct-read exclusion for a moderation-hidden note.
- Widget and navigation tests for the note report action.

## 2. Moderate note title and description on creation

Call moderation in `createNote` after input validation but before its Firestore
transaction. Combine the title and optional subtitle as labeled text fields so
one provider request covers both.

Use a fail-closed publication policy for note metadata:

- `allow`: continue note creation.
- `sensitive`, `review`, or `hidden`: do not publish the note; return a stable
  callable error code that the client maps to neutral localized copy.
- `pending`: do not publish; ask the user to retry later.

This is stricter than the current message policy because note titles and
descriptions are displayed directly on the map and do not have a
sensitive-content reveal UI.

Additional work:

- Bind `OPENAI_API_KEY` to `createNote`.
- Apply the existing account restriction check and decide whether rejected
  attempts contribute moderation points. If they do, update the user and create
  a notice transactionally without retaining public content.
- Record a minimal server-only moderation audit event for rejected drafts.
  Avoid retaining rejected user text longer than operationally necessary.
- Return structured callable details such as `reason: "content_not_allowed"`
  rather than exposing provider categories to the client.
- Add function tests for all actions, provider unavailability, empty subtitle,
  retry/idempotency, and absence of a place document after rejection.

Future title/subtitle editing must use the same moderation helper before it is
introduced.

## 3. Image moderation

The current OpenAI moderation model already used by the project accepts image
input. Extend the provider helper to accept text and one or more validated image
parts and aggregate the returned decision conservatively.

### Message images

The current ordering can be retained:

1. Client compresses and uploads images to an unguessable, user-owned path.
2. `sendMessage` validates every expected object and downloads the bytes with
   the Admin SDK.
3. The function sends text and image data to moderation before the Firestore
   transaction publishes the message.
4. A non-allow image decision prevents public attachment using the same
   message moderation policy and deletes all submitted objects.

Also add best-effort client cleanup when `sendMessage` fails. This closes the
ordinary error path that currently leaves uploaded but unreferenced objects.

An authenticated client can still upload an orphan object without invoking the
callable. The object is not discoverable through Firestore, but production
hardening should add a scheduled orphan cleanup or Storage-finalize quarantine
flow. A scheduled cleanup is simpler for the first release; a quarantine flow
gives stronger guarantees but requires an upload-session design.

### Map-pin images

- Bind `OPENAI_API_KEY` to `setNotePinImage`.
- After metadata validation, download and moderate the thumbnail before
  attaching its path to the note.
- On any non-allow result, delete the candidate object, retain the previous pin
  image, and return a localized-safe error.
- On provider unavailability, fail closed and delete the candidate object.
- If an administrator later hides an attached image, detach it before deleting
  the Storage object.

### Existing images

Run a resumable, dry-run-capable backfill over referenced message and pin images
before submission. The script should:

- checkpoint progress;
- respect provider rate limits;
- skip missing and already-reviewed objects;
- queue or hide non-allow content with the same production policy;
- write audit metadata without logging image bytes or signed URLs.

### Tests

- Multimodal provider payload and response normalization.
- Mixed safe/unsafe text and image decisions.
- Missing object, wrong MIME type, oversize object, provider timeout, and
  partial cleanup failures.
- No Firestore reference is published before moderation succeeds.
- Existing pin image remains attached when a replacement is rejected.

## 4. Localize the report flow

The localization change covers more than `ReportMessageScreen`:

- report screen title, prompt, privacy explanation, submit/progress labels, and
  error copy;
- message action-sheet label and inline flag tooltip;
- report-submitted confirmation;
- note report entry point and target-specific wording;
- report reason labels and callable error mapping.

Add the keys to every release locale (`en`, `ja`, `ko`, `zh_Hans`, and
`zh_Hant`), with `app_zh.arb` continuing to mirror Simplified Chinese. Keep
English as the complete ARB schema and generate Dart localization files rather
than editing them manually.

Map canonical reason codes to localized labels in a presentation helper. Do not
send the localized label to the backend.

Verification:

- `flutter gen-l10n`
- locale-key parity and formatter tests
- report-screen widget tests in Japanese and English
- a manual pass at narrow phone widths and with increased text scale

The administrator-only moderation screen still contains English literals. It
is outside the user-facing report-flow scope and can remain English unless the
administrator workflow also needs Japanese localization.

## Delivery sequence

1. Migrate to the generic target/reason schema
2. Localized generic report screen and reason codes
3. Note reporting and administrator note actions
4. Fail-closed note title/subtitle moderation
5. Message and pin image moderation plus cleanup
6. Existing-image backfill
7. Emulator/function tests, Flutter tests, security-rule tests, and deployment
   runbook updates

## Relative size

| Work item | Size | Main risk |
| --- | --- | --- |
| Report-flow localization | S | Locale key parity and reason-code migration |
| Note title/description moderation | M | Fail-closed UX and retry semantics |
| Note reporting | M-L | Generic admin review and hidden-note behavior |
| Image moderation | L | Upload ordering, cleanup, and existing images |
| Full regression/deployment verification | M | Rules, indexes, emulators, and secrets |

The four-item change is approximately one medium feature rather than four small
UI tasks. The image path and generic administrator review are the critical
pieces.

## Separate user-blocking branch

User blocking should add a server-owned edge such as
`userBlocks/{blockerUid}_{blockedUid}` and a callable to create/remove it. The
product decision should define whether blocking is one-way or also prevents the
blocked account from interacting with the blocker.

Expected impact areas:

- block/unblock actions on public profiles and message actions;
- map-pin filtering by blocked creator;
- message-list filtering by blocked author;
- direct note access and invite behavior;
- likes, follows, visits, replies, and notifications;
- counters when filtered content is omitted;
- Firestore rules and callable enforcement so a modified client cannot bypass
  interaction restrictions;
- tests for both sides of the relationship and unblock restoration.

Because map pins are returned by a callable, blocked creator IDs can be applied
server-side there. Message filtering needs a deliberate decision between
server-side reads and client-side display filtering; client-only filtering is
not sufficient for interaction enforcement.
