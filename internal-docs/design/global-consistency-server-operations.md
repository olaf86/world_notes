# Global consistency server-operation matrix

## Purpose and baseline

This document inventories the currently deployed server operations and the
planned operations required by the multi-world database design. The initial
deployment has three worlds, but the consistency model supports adding more.
It evaluates the consistency boundary, expected latency, and unresolved risks
of each operation.

Baseline:

- Source commit: `38eadb1`
- Firestore edition: Standard
- Current database: Tokyo `(default)`
- Current Functions region: `asia-northeast1`
- Initial world databases: Asia, Europe, North America
- Proposed authority model: one authority world per independently replicated
  entity, distributed across the active world databases
- User-owned global data authority: the user's immutable `homeWorld`
- Global operation record and durable work item: one
  `globalOperations/{operationId}` document colocated with the entity in its
  `authorityWorld`
- Proposed local read models: one mirror in each active world database

The latency figures below are engineering estimates, not measured SLOs. They
exclude the user's mobile-network round trip unless otherwise stated.

## Consistency classes

| Code | Meaning | Success guarantee |
| --- | --- | --- |
| `W` | World-local transaction | Exact within the selected world database |
| `G` | Global-entity authority transaction | Exact in that entity's `authorityWorld` |
| `GM` | Authority write plus enforcement-mirror acknowledgement | Exact in the authority and applied to all safety-critical mirrors when the operation becomes `complete` |
| `E` | Eventually replicated global data | Authority state is exact; local mirrors may lag |
| `S` | Durable saga/outbox | Logical operation is accepted; cleanup and side effects converge asynchronously |
| `X` | External provider involved | Firestore atomicity does not include the external system |
| `B` | Scheduled or background processing | Completion is bounded by schedule/backlog rather than request latency |

## Latency bands

These are warm-instance backend estimates. A Cloud Run Functions cold start can
add roughly 0.5–3 seconds. Mobile access can add approximately 50–300 ms or more
depending on the user's network.

| Band | Expected warm latency | Typical shape |
| --- | --- | --- |
| `L0` | 100–400 ms | One regional read or write |
| `L1` | 200–800 ms | Regional transaction with several document reads |
| `L2` | 300–1,200 ms | Multiple regional queries or small batch |
| `G1` | 200–800 ms local; 300–1,200 ms routed | One small transaction in the entity's authority world |
| `GM-COMPLETE` | normally 600 ms–5 s | Asynchronous propagation and acknowledgement by the operation's snapshotted required worlds |
| `X1` | 800 ms–4 s | Text moderation, Auth, FCM, or small Storage work |
| `X2` | 1–8 s | Image download/moderation or several Storage objects |
| `JOB` | seconds–minutes | Durable worker or bounded batch |
| `SCHED-1M` | 0–60 s plus backlog | One-minute scheduler |
| `SCHED-24H` | 0–24 h plus backlog | Daily scheduler |

Cross-region failures can exceed these bands. Every global command returns
`accepted` after `G1`; a `GM` operation remains `pending` rather than report
globally completed while an enforcement mirror is unavailable.

## Current callable operations

### Notes and messages

| Operation | Current resources and side effects | Proposed class | Expected latency | Consistency after success | Issues requiring attention |
| --- | --- | --- | --- | --- | --- |
| `createNote` | OpenAI text moderation; `users`, `places`, `noteStates`, optional secret and counter | Current: `W + X`; proposed acceptance path: `W/S`; `G/S` only for violation events | Current: `X1`; proposed acceptance: `L1` | Current note and per-world active-note count are exact after moderation. Proposed path creates a locally exact public-pending note and quota reservation, then finalizes moderation asynchronously. | Move `activeNoteCount` out of globally replicated user fields. The same `places/{placeId}` can represent pending work; no separate queue is required. Rejection hides the aggregate root, so child data does not need synchronous rollback. |
| `setNotePinImage` | Storage download/delete, OpenAI image moderation, `places` transaction | Current: `W + X`; proposed acceptance: `W/S` followed by `S + X + W` | Current: `X2`; proposed acceptance: `L1` | Proposed path attaches a public-pending candidate locally, then allows it or restores/removes it asynchronously | Give the pin candidate its own moderation action; rejecting an image must not hide the note. Retain the previous path until the candidate verdict and clean up Storage durably. |
| `setNoteTheme` | `places`; two-direction block check | `W` with local block enforcement mirror | `L1` | Exact in the note's world | Safe only after block operations acknowledge the local enforcement mirror. |
| `archiveNote` | `places`, `users.activeNoteCount`, `noteStates`; invite revocation after commit | `W + S` | `L1–L2` | Archive and per-world slot release are exact locally; invite revocation converges | Move the counter to local per-world user state. Invite revocation still needs an outbox rather than best-effort post-commit work. |
| `sendMessage` | Storage reads/deletes, OpenAI moderation, block/account-safety checks, `places`, message, counters, note state, review | Current: `W + X`; proposed acceptance path: `W/S` | Current: `X1` text-only; `X2` with images. Proposed acceptance: `L1` | Current publication and local capacity are exact in the world. In the proposed path, the `messages/{messageId}` record and slot reservation are exact; moderation converges asynchronously. | Current callable waits for external moderation. The same message document can carry `moderationAction: pending`; a separate submission collection is not required. Public-before-verdict versus sender-only-before-verdict is a product safety decision. |
| `deleteMessage` | Message update and Storage cleanup | `W + X` | `L1–X2` | Message tombstone is exact locally; object deletion is eventual | Retry-safe object cleanup and a cleanup queue are needed. |
| `cancelScheduledMessage` | Message delete, message-slot counter, `places`, Storage cleanup | `W + X` | `L1–X2` | Slot release and message deletion are exact locally | Storage deletion remains outside the transaction. |
| `setMessageLike` | Message-like edge and message aggregate | `W` | `L1` | Exact in the message's world | A highly popular message can hotspot its aggregate document; shard only if observed. |
| `setNoteLike` | Note-like edge and `places.likeCount` | `W` | `L1` | Exact in the note's world | A highly popular note can hotspot `places/{id}`. Blocking relies on a current local enforcement mirror. |
| `recordNoteVisit` | Visitor edge, user note state, `places.visitorCount` | `W` | `L1` | Exact in the note's world | Popular-note visitor-count contention. The edge is idempotent, but the aggregate remains a shared document. |
| `setFootprintEnabled` | `places`; block check | `W` | `L1` | Exact in the note's world | No global transaction required. |
| `setNotePassword` | Password hash, secret document, `places` metadata including optional `lockHint` | `W` | `L1`, occasionally `L2` | Secret and visible lock metadata commit in one world batch | `lockHint` is intentionally outside moderation scope; retain length/type validation. World-routed Firestore context is required, with no global data dependency. |
| `unlockNote` | Attempts, secret, block check, user profile read, member grant | `W` | `L1–L2` | Access grant is exact locally | The public/member profile mirror must be present. Brute-force limits are intentionally per-world unless product policy says otherwise. |

### Reports and administration

| Operation | Current resources and side effects | Proposed class | Expected latency | Consistency after success | Issues requiring attention |
| --- | --- | --- | --- | --- | --- |
| `reportNote` | `places`, membership, `reports`, `moderationReviews`, regional rate limit | `W` | `L1` | Report and review queue update are atomic in the content world | Add `worldId`/`databaseId`. Keep the cooldown regional unless a global abuse limit is explicitly required. |
| `reportMessage` | Note/message, `reports`, message/report counters, `moderationReviews`, rate limit | `W` | `L1` | Report, message count, and review update are atomic locally | Report resolution must identify `worldId + targetPath`, not `targetId` alone. |
| `adminListModerationReviews` | One default-DB query today | Federated read over three `W` stores | `L2`, approximately 200 ms–1.5 s | Each returned item is exact in its source world; merged ordering is snapshot-as-of-query, not one cross-world snapshot | Query all worlds in parallel, merge by `createdAt`, and return an opaque world-aware cursor. |
| `adminReviewMessage` | Message, review, matching reports, audit log, Storage deletes | `W + X` | `L1–X2` | Moderation decision, review, reports, and audit commit atomically in the source world | Route by trusted `worldId`. Storage deletion remains asynchronous. Current report query is not sufficiently world/path-specific. |
| `adminReviewNote` | Place, review, reports, audit log, optional Storage delete | `W + X` | `L1–X2` | Moderation state and review records commit atomically locally | Same trusted world routing and Storage cleanup requirements. |

### Current general invites and proposed note-administrator delegation

| Operation | Current resources and side effects | Proposed class | Expected latency | Consistency after success | Issues requiring attention |
| --- | --- | --- | --- | --- | --- |
| `getInviteLink` | Local note authorization and reusable member-invite query | Retire | N/A | N/A | General private-note invitations are removed; passwords remain the ordinary private-access mechanism. |
| `createInviteLink` | Local note authorization, invite query, random bearer-token write | Retire | N/A | N/A | Remove the reusable bearer link rather than repairing its concurrent-create race. |
| `claimInvite` | Invite, note, block documents, member grant, use count in one transaction | Retire | N/A | N/A | No general invite claim or `invited: true` membership is created in the target design. |
| `revokeInvite` | Query and batch-update local member invites | Retire | N/A | N/A | Remove with the general member-invite model. |
| `revokeNoteAccess` | Local member deletion | `W` | `L0–L1` | Exact locally | No global dependency. |
| `grantNoteMaintainer` | Immediate promotion of an existing member | Retire/replace | N/A | N/A | Replace with explicit target-bound invitation and recipient acceptance; ordinary membership is no longer a prerequisite. |
| `createNoteAdministratorInvite` | Note, inviter authority, target UID, block/safety checks, and a pending invitation | `W/S` | `L1` | Pending invitation is exact in the note world; notification delivery is eventual | Creator or active administrator may invite; use a deterministic pending identity and signed world hint. |
| `acceptNoteAdministratorInvite` | Invitation, target identity, note, block/safety checks, and administrator grant | `W` | `L1` | Acceptance and administrator grant commit atomically in the note world | Single-use and target-UID-bound; selected-world UI changes only after success and consent. |
| `revokeNoteAdministratorInvite` | Pending invitation transition | `W` | `L1` | A revoked pending invitation cannot be accepted | Any active administrator may cancel it; creator is immutable. |
| `revokeNoteMaintainer` | Existing administrator grant | `W` | `L1` | Revocation is exact in the note world | Any active administrator may remove any other non-creator administrator; every change is audited. |

### Profiles, social graph, blocking, and settings

| Operation | Current resources and side effects | Proposed class | Expected latency | Consistency after success | Issues requiring attention |
| --- | --- | --- | --- | --- | --- |
| `updateDisplayName` | `users`, `publicProfiles`, Firebase Auth, then unbounded member/place snapshot rewrites | `G + E + S + X` | Acceptance `G1`; propagation `JOB` | Home-world profile authority is exact; world snapshots converge | Display names are intentionally outside moderation scope. Do not wait for every snapshot rewrite. Auth and the profile authority need reconciliation, and projections need revision guards against out-of-order events. |
| `setLanguagePreference` | Private `users` update | `G + E` | Acceptance `G1` | Home-world preference authority is exact; mirrors converge | Low risk. Last-writer-wins is acceptable if revisioned. |
| `setUserFollow` | Users/profiles, follow edge, profile counters, notice/FCM | Owner-world `W`, then `E + S` | `L1`; notice delivery async | Edge is exact at its owner. Other worlds and counts converge | Remove profile-counter writes from the edge transaction. Define owner region. Check global block authority/enforcement mirror. Use notification outbox. |
| `setUserBlock` | Block edge, two follow edges, profile counters, full note/message cleanup | `GM + S` | Acceptance `G1`; logical completion `GM-COMPLETE`; cleanup `JOB` | After `complete`, all worlds deny the relationship; physical follow/member/message cleanup converges | The blocker's home world owns the edge. Cross-world cleanup must be durable and independently retryable. Unblock uses a revisioned tombstone and has the same mirror requirement. |
| `registerFcmToken` | User token document | `G` or a single notification-control store | `G1` | Token registry is exact in its authority | Never independently replicate and send from all worlds, or pushes can duplicate. |
| `deleteFcmToken` | User token delete | `G` | `G1` | Token removal is exact in its authority | Use tombstone/revision if token mirrors exist. |
| `setMyNotesNotificationEnabled` | Notification preference | `G + E` | `G1` | Home-world setting authority is exact; mirrors converge | Notification delivery owner must consult the authority or sufficiently fresh state. |
| `setMyNotesNotificationPreviewEnabled` | Notification preview preference | `G + E` | `G1` | Home-world setting authority is exact; mirrors converge | Same delivery-owner requirement. |

### Discovery and access

| Operation | Current resources and side effects | Proposed class | Expected latency | Consistency after success | Issues requiring attention |
| --- | --- | --- | --- | --- | --- |
| `listMapPins` | Several geohash queries, user entitlement, note state, social edges, two block reads per distinct creator | Local read model | `L2`, approximately 200 ms–1.5 s | Returns one internally consistent response from the selected world, subject to global-mirror lag | Completed blocks must already be in the local mirror. Worst-case block checks are about 240 reads for 120 distinct creators. Consider a server-only relationship index if measured cost/latency is high. |
| `validateNoteAccess` | Note read, user entitlement, block check, location validation | Local read model with safety mirror | `L1` | Exact for world content; safety is exact after `GM` block completion | No cross-region authority read should be added to this hot path. |

## Current scheduled and event-driven operations

| Operation | Current behavior | Proposed class | Expected latency | Consistency after completion | Issues requiring attention |
| --- | --- | --- | --- | --- | --- |
| `aggregatePublishedMessages` | Every minute; reads at most 100 due scheduled messages, updates note/message counters, sends FCM | Per-world `B/W + S` | `SCHED-1M` | Each applied message is locally transactional | Capacity is only 100 messages per world per minute and the function does not drain the backlog in one run. Notification after commit needs an outbox to avoid loss/duplication. |
| `archiveExpiredNotes` | Daily; batches 200 notes; updates note state and the per-world active-note count | Per-world `B/W` | `SCHED-24H` | Archive and slot release are exact in each world | Keep the counter local and do not emit a global count event. |
| `sync*ProfileSnapshots` | Per-world Firestore trigger; pages through active creator places and memberships | Per-world `B/E` | seconds–minutes | Eventually applies the latest profile revision | Every page re-reads its targets in a transaction and updates only an older snapshot revision. Duplicate and out-of-order profile events therefore cannot roll a newer snapshot back. |

## Planned Global Consistency Layer operations

| Planned operation | Responsibility | Class | Expected latency | Required guarantee | Main failure mode and mitigation |
| --- | --- | --- | --- | --- | --- |
| `executeGlobalCommand` | Resolve `authorityWorld`, authenticate, validate operation ID, serialize the mutation, and atomically write authority state plus the operation work item | `G` | Acceptance `G1` | Idempotent authority commit | Retry with the same operation ID; reject a reused ID with different payload |
| `applySafetyStateToWorlds` | Copy block/account-safety state to all enforcement mirrors | `GM` | `GM-COMPLETE` asynchronously | A completed safety command is visible to all world write paths | If one world is unavailable, leave operation pending and do not claim global completion |
| `replicateGlobalEntity` | Replicate profiles, settings, notices, social edges and tombstones | `E` | normally seconds; backlog-dependent | Monotonic revision application | At-least-once and out-of-order delivery; apply only newer revisions |
| `applyAccountSafetyEvent` | Route to the subject user's home world, deduplicate the moderation event, and update points/restriction/BAN in authority order | `G` | `G1`; asynchronous after rejected publication | No lost violation events | Immutable event ID plus one home-world authority transaction |
| `adminUpdateAccountSafety` | Apply an authenticated administrator point adjustment or restriction/BAN override in the subject user's home world | `G + GM` | Acceptance `G1`; completion `GM-COMPLETE` | Every override is audited and globally enforced after completion | Require `admin: true`, a reason and an idempotency key; deny direct client writes to authority and mirrors |
| `runFirestoreCleanup` | Execute typed, local Firestore cleanup for block, invite, moderation, account, and other mirrored-entity workflows | `S/JOB` | seconds–minutes | Each cleanup intent eventually reaches its local terminal state | Deterministic job IDs, leases, bounded batches, checkpoints, and a scheduled reconciler |
| `runStorageCleanup` | Delete regional Storage objects after their Firestore references no longer require them | `S/X/JOB` | seconds–minutes | Referenced objects are retained and obsolete objects are eventually absent | Separate queue and deployment from Firestore cleanup; deletion treats an already-absent object as success |
| `reconcileCleanupJobs` | Resume expired leases and old pending cleanup jobs in one target world | `B/JOB` | reconciliation interval | Trigger loss or worker termination cannot permanently strand cleanup | Reuse the same runner and handlers as the event-driven fast path; alert on age and repeated attempts |
| `materializeSocialStats` | Build follower/following counts from owned/replayed social edges | `E/JOB` | seconds–tens of seconds | Counts converge to edge truth | Sharded counters plus periodic edge-based reconciliation |
| `federatedModerationList` | Query all world review queues and merge/cursor results | Federated read | `L2` | No item is lost from pagination | World-aware cursor and deterministic `(createdAt, worldId, reviewId)` order |
| `routeNoteAdministratorInvite` | Route a target-bound administrator invitation to its authoritative note world | Signed route | `L0–L1` | Never accepts in the wrong world or for the wrong UID | Versioned signed world hint plus unguessable nonce; no global invite directory |
| `acceptPendingNote` | Validate the draft, reserve one per-world active-note slot, create the note/secret/state with pending moderation | `W/S` | `L1` | Pending note creation, public availability, and quota reservation are atomic locally | Use a client-generated note ID for idempotency. Child actions may proceed optimistically while the note is pending. |
| `evaluatePendingNote` | Evaluate title/description and allow, label, hide, or retry the pending note | `S + X + W`; `G/S` for violation event | Normally `X1`; retry-dependent | Moderation finalization is exact locally. Rejection atomically hides/closes the aggregate root and releases the active-note slot exactly once. | Finalize only when the immutable note is still `pending`; a separate moderation revision is unnecessary. Child data can remain dormant behind the hidden parent and be cleaned up later by retention policy. |
| `acceptPendingMessage` | Validate the sender and note, reserve one local message slot, and create `messages/{messageId}` with a pending moderation state | `W/S` | `L1` | Message acceptance and capacity reservation are atomic in the content world | Use the client-generated message ID as an idempotency key. Whether pending content is public or sender-only is controlled by `isPubliclyVisible`. |
| `evaluatePendingMessage` | Load pending message text/images, call the provider, and allow, label, hide, or retry it | `S + X + W`; `G/S` for violation event | Normally `X1` text-only or `X2` with images; retry-dependent | The moderation state transition is exact locally. Hidden content is soft-deleted; image deletion and global account-safety updates converge. | Provider calls are not transactional. Use task-level retry/backoff and finalize only while the immutable message is still `pending`. Store leases/attempts only if Firestore itself is chosen as the worker queue. |
| `enqueueNotification` | Transactionally record notification intent with the source operation | `W/S` or `G/S` | Added within source transaction | No lost intent | Outbox record with globally unique event ID |
| `deliverNotification` | Single-owner FCM delivery and token cleanup | `S/X` | normally seconds | At-least-once processing, application-level dedupe | FCM is not part of the Firestore transaction; persist delivery attempts and collapse duplicate event IDs |
| `reconcileGlobalMirrors` | Compare each authority revision/checksum with its world mirrors | `B` | minutes–hours | Detect and repair permanent drift | Partitioned scan by `authorityWorld`, checkpoints, and repair audit log |
| `monitorReplicationLag` | Publish per-world high-water marks and alert on lag | `B` | monitoring interval | Safety operations never silently remain pending | Alert by collection/world and expose pending operation age |

## Resolved design decisions

### Active-note quota

The note quota is independent in each world:

- Free users: 20 active notes per world
- Premium users: 200 active notes per world

Creating notes in multiple worlds is explicitly allowed. The purpose of the
quota is to prevent accidental or abusive over-creation, not to enforce a
strict global entitlement total.

`activeNoteCount` must therefore be local-only state. It must not be included
in whole-document replication of the global `users/{uid}` document. The path
does not need a `worldState/main` subcollection layer. A simpler path is:

```text
userUsage/{uid}
  activeNoteCount
  updatedAt
```

The same path exists independently in every active world database. `createNote`,
`archiveNote`, and `archiveExpiredNotes` update it transactionally with their
local note changes. The global user mirror continues to provide `isPremium`,
which determines whether the local limit is 20 or 200.

### Moderation timing

The current implementation evaluates content before the authoritative content
write:

| Content | Current evaluation timing | Provider unavailable | Current visibility |
| --- | --- | --- | --- |
| Note title and description | In `createNote`, before the note transaction | Request fails | Never published unchecked |
| Note pin image | In `setNotePinImage`, after upload/download but before attachment to the note | Request fails and the candidate image is deleted | Previous pin remains |
| Message text | In `sendMessage`, before the message transaction | Stored as `moderationAction: pending` | An immediate message can remain publicly visible pending later evaluation |
| Message image | In `sendMessage`, after uploaded images are downloaded and before the message transaction | Request fails and candidate images are deleted | Never published unchecked |
| Scheduled message | At submission time, not at `publishAt` | Same as the corresponding text/image case | If accepted, publication waits for the existing one-minute scheduler |

The current scheduler only publishes due scheduled messages. It does not
re-evaluate `moderationAction: pending`; that re-evaluator is documented as
future work but is not implemented.

For message-send UX, prefer event-driven post-write moderation over a periodic
scan. A separate submission collection is not required; the existing message
document can be the moderation work item:

```text
places/{placeId}/messages/{messageId}
  userId
  content
  imageStoragePaths
  publishAt
  moderationAction: pending | allow | sensitive | review | hidden
  moderationPolicyVersion
  moderationCheckedAt
  isPubliclyVisible
  isDeleted
```

1. The callable validates access, creates the pending message, and reserves one
   `messageSlots` unit in a local transaction, then returns immediately.
2. The client immediately shows the sender a pending bubble.
3. A Firestore-triggered worker or Cloud Task evaluates the text and images.
4. On `allow`, `sensitive`, or `review`, one local transaction finalizes the
   moderation fields. If the product uses sender-only pending messages, an
   immediate message also becomes public and updates public aggregates there.
5. On `hidden`, a local transaction soft-deletes the content. Whether the
   reserved slot is retained as a tombstone or released must be consistent
   with the product's 1,000-message capacity policy. Image cleanup and global
   account-safety events remain durable asynchronous work.
6. On provider unavailability, the worker retries with backoff. Unchecked
   content remains in `pending`.

`moderationReviews` and `moderationAuditLogs` do not coordinate background
execution: reviews are the administrator work queue, while audit logs preserve
decisions after they occur. Worker retries and claims belong to the task
runner, not automatically to every content document.

The three previously proposed worker-control fields are optional:

| Field | Is it required on content? | When it is useful | Recommended placement |
| --- | --- | --- | --- |
| `moderationAttemptCount` | No | Maximum-attempt policy, support diagnostics, or a Firestore-driven retry queue | Cloud Tasks retry metadata, structured logs, or a server-only `moderationJobs` document |
| `moderationLeaseUntil` | No | Several workers scan/claim the same pending documents and duplicate provider calls must be suppressed | Server-only `moderationJobs` document; omit when task delivery plus idempotent finalization is sufficient |
| `moderationRevision` | No for immutable notes/messages | Editable content, overlapping re-evaluations, or a mutable image candidate could receive an old verdict | Prefer an immutable input hash/candidate ID; use a revision only for a genuinely mutable moderation input |

For the current immutable content, the finalization transaction only needs to
verify the relevant terminal guard:

```text
note:    moderationAction == pending
message: moderationAction == pending && isDeleted != true
```

If an administrator or another worker has already finalized the item, the
late worker becomes a no-op. Duplicate provider calls may still cost money, but
they cannot overwrite the terminal decision.

For replaceable pin images, compare the candidate ID/path captured by the task
with the currently attached candidate before applying the result. That identity
guard is more precise than a generic note-level moderation revision.

A one-minute scheduled moderation job is useful only as a repair/drain
mechanism. Using it as the primary path adds 0–60 seconds plus backlog to every
message. The regional acceptance response should normally remain within
regional `L1`, while actual publication still takes roughly `X1` for text and
`X2` for images. This improves perceived responsiveness rather than reducing
the provider's evaluation time or per-message moderation cost.

There are two valid visibility policies for the pending interval:

- **Sender-only pending:** set `isPubliclyVisible: false`, then publish after a
  non-hidden verdict. This reuses `messages` while preventing unchecked
  exposure.
- **Public pending (post-moderation):** set `isPubliclyVisible: true`
  immediately. Most safe messages incur no visible delay; a later `hidden`
  verdict removes the exceptional unsafe message.

Public pending is operationally simpler and is a reasonable product decision
when a short unsafe-content exposure window is explicitly accepted. Blocking
does not close that window: it filters known user pairs, while the first unsafe
post is still visible to every non-blocking viewer. Push notifications,
previews, likes, and other fan-out should therefore wait for a non-pending
verdict even if the message body is visible immediately.

If sender-only pending is selected, the current Storage rule is insufficient:
message images are readable by any authenticated user regardless of the
message's Firestore visibility. Image reads must be restricted to the author
or to an associated publicly visible message, or served through a trusted
download endpoint. Public-pending images intentionally accept the same
temporary exposure as their message.

### Moderation field normalization

For notes, `isModerationHidden` and `moderationAction` represent the same
moderation decision. Keep only `moderationAction` as the source of truth:

```text
pending | allow | sensitive | review  -> visible
hidden                               -> hidden
```

For the optimistic-publication state machine, `moderationAction` is the only
field that controls visibility or authorization. Retain the following two
non-authoritative fields on note and message content as compact audit metadata:

```text
moderationPolicyVersion
moderationCheckedAt
```

Create a pending item with only `moderationAction: pending`. When the provider
evaluation completes, write `moderationAction`, `moderationPolicyVersion`, and
`moderationCheckedAt` together in the same finalization transaction. A future
automated re-evaluation must likewise replace all three together so the
metadata always describes the automated verdict currently stored on the
content.

`moderationCheckedAt` means the time of the latest completed automated provider
evaluation. Human review remains separately represented by
`moderationReviewedAt`; an administrator decision must not overwrite
`moderationCheckedAt`. Security rules, visibility filters, and business logic
must not depend on either audit field.

Each `moderationPolicyVersion` must resolve to an immutable policy definition
that records the provider, model identifier, thresholds, and relevant prompt or
rule-set version. Without that version-to-configuration mapping, these two
content fields prove when and under which named policy an item was evaluated,
but not which concrete model configuration produced the verdict.

Current Firestore audit coverage is intentionally asymmetric:

- `moderationReviews` stores non-allow/provider-review and user-reported items;
- `moderationAuditLogs` stores automated rejections and administrator
  decisions;
- normal `allow` decisions are not written to either collection, and the
  current moderation function does not emit a complete structured success log.

The selected audit policy is:

- retain durable Firestore audit/review data for non-allow and administrator
  decisions;
- retain policy version and automated evaluation time on every evaluated
  content document, including ordinary `allow`;
- do not require a separate, per-content Firestore audit document for ordinary
  `allow`;
- add a structured operational log for every worker result if per-item
  troubleshooting is desired, with an explicitly configured retention period.

This preserves enough local evidence to identify when and under which policy an
allowed item was evaluated. The provider/model and full scores remain in
review/audit/operational logs where applicable; they need not be duplicated on
every content document unless a later compliance requirement calls for it.

Firestore bills a document write, not one write per field. Removing
`moderationPolicyVersion` or `moderationCheckedAt` from an update that already
sets `moderationAction` does not reduce the number of document writes. It
would only reduce a small amount of document and index storage. Exempt both
fields from single-field indexing initially; add a policy-version index only
if an actual query for old-policy content is introduced.

The current implementation already writes `moderationPolicyVersion`.
`moderationCheckedAt` must be added to the content finalization update when the
optimistic worker flow is implemented.

Note discoverability is then derived from independent axes:

```text
moderationAction != hidden
&& isArchived == false
&& publishAt <= now
&& expiresAt > now
```

`isOpen` remains separate because it controls writability, not visibility.
Likewise, scheduling and archive lifecycle must not be encoded into
`moderationAction`.

The current code and Security Rules read `isModerationHidden`, so removal
requires a staged migration: dual-read/dual-write during deployment, backfill
`moderationAction` on legacy notes, switch every reader and rule, then remove
the boolean. If a boolean is retained solely to optimize a query, name it after
the projection it serves, such as `isDiscoverable`, and treat it as a derived
materialized field rather than a second moderation authority.

Messages still need fields for non-moderation axes:

- `moderationAction`: provider/administrator policy decision.
- `isDeleted` and `deletedReason`: author deletion versus moderation tombstone.
- `isPubliclyVisible`: scheduled-publication state.

`isSensitive` can be derived from `moderationAction in [sensitive, review]`.
`reviewRequired` should be derived from the moderation review queue rather than
duplicated on content, because a user report can open a review while the
automated `moderationAction` remains `allow`. The currently always-true
`isVisible` field should also be removed unless a separate non-moderation
visibility use case is defined.

### Optimistic note creation

`createNote` can also return before provider evaluation. The same
`places/{placeId}` document should represent the pending note:

```text
places/{placeId}
  moderationAction: pending
  moderationPolicyVersion
  moderationCheckedAt
```

The two audit fields are absent while the initial evaluation is pending and
are added with its terminal verdict.

The optimistic note flow can use the same public-pending policy as messages:

1. Validate the draft, reserve one active-note slot, and create the pending
   `places` document, owner note state, and optional secret in one local
   transaction.
2. Return the note ID immediately and expose the new pin normally while its
   `moderationAction` is `pending`.
3. Permit messages, invites, likes, visits, and membership changes normally.
   Each child operation keeps its own authorization and moderation checks.
4. Evaluate the title and description through an event-driven worker.
5. On a non-hidden verdict, finalize the moderation fields without changing
   visibility. On rejection, one local transaction sets
   `moderationAction: hidden`, closes the note, and releases the per-world
   active-note slot exactly once.

The rejection transaction does not need to delete or compensate child
messages, invite claims, membership, likes, visits, or aggregates. They become
dormant behind the hidden aggregate root. This matches the existing
administrator note-hide behavior, which changes the parent moderation state
without recursively deleting its subcollections. A later retention worker can
delete terminally rejected subtrees if storage cost justifies it.

Every child mutation must read the parent note inside its local transaction.
Then a concurrent rejection update makes Firestore retry that mutation against
the hidden parent, preventing a successful child commit after rejection.
Non-transactional best-effort side effects must independently re-check the
parent or tolerate becoming dormant.

If an administrator can later restore an automatically rejected note, the
restore transaction must reserve an active-note slot again before making it
visible. Otherwise releasing the slot on rejection and later restoring the
note could exceed the per-world quota.

Two boundaries still require explicit treatment:

- Current Firestore rules do not consistently make a hidden private note
  unreadable to an existing member. Every non-owner access branch must require
  `moderationAction != hidden` if rejection is intended to hide the entire
  subtree from all other users.
- Storage objects and already-sent push notifications are outside the parent
  Firestore access boundary. Rejected images need asynchronous deletion, and
  irreversible notification fan-out should preferably wait for a non-pending
  note verdict even when interactive child writes remain optimistic.

Scheduled notes should always be evaluated immediately after creation and stay
non-public until both the verdict is acceptable and `publishAt` has arrived.
Pin-image replacement may also be public-pending when the temporary image
exposure is accepted. Retain the previous path until the verdict so rejection
can restore it, then delete the rejected candidate asynchronously.

### Moderation scope and optimistic publication

| Public input | Current coverage | Optimistic-publication design | Rejection behavior | Assessment |
| --- | --- | --- | --- | --- |
| Note title/subtitle | Synchronous before creation | Create and expose the note with `moderationAction: pending`; evaluate by event | Hide/close the parent and release its local quota slot | Recommended |
| Message text | Synchronous before message transaction | Create the normal message as `pending`; evaluate by event | Soft-delete the message and emit a global safety event | Recommended |
| Message images | Synchronous download/evaluation before message transaction | Attach final-path images to the public-pending message | Remove image references, soft-delete when required, and enqueue object deletion | Recommended when temporary/cached exposure is accepted |
| Pin image | Synchronous before attachment | Attach a candidate immediately with its own pending action and retain the previous path | Restore/remove the candidate and enqueue its deletion; do not hide the note | Recommended with durable cleanup |
| Lock hint | Intentionally outside moderation scope | Apply immediately with the lock update after type/length validation | Not applicable | No moderation needed |
| Display name | Intentionally outside moderation scope | Apply immediately and replicate by profile revision | Not applicable | No moderation needed |
| Profile photo | OAuth photo URL; no app upload feature | Publish through the normal profile path | Not applicable | Outside current moderation scope; reconsider only if direct photo upload is added |
| Report reason | Fixed enum, no free-form public text | No moderation job | Reject invalid enum synchronously | No moderation needed |
| Theme, icon, color, password/pattern | Bounded enum/value or secret | Validate synchronously | Reject invalid input | No moderation needed |

The moderation action belongs to the independently rejectable publication
unit. A rejected pin image must not set the entire note's `moderationAction` to
`hidden`; the image candidate needs its own action and candidate ID. Conversely, note
title and subtitle are one publication unit, so one note-level action is
sufficient.

The initial moderation scope is intentionally limited to:

- note title and subtitle;
- message text;
- message images;
- note pin images.

Lock hints, display names, OAuth profile photos, report reason enums, themes,
icons, colors, and password/pattern secrets are outside moderation scope.

### Distributed authority and world routing

Global entities use distributed single authority, not three writable masters.
Each independently replicated entity has exactly one `authorityWorld`; only
that world allocates its revision and commits its authoritative mutation.

For user-owned global entities, the authority is derived from an immutable
home assignment:

```text
userHomes/{uid}
  world: asia | europe | northAmerica
  epoch: 1
```

- `homeWorld`: the user's authority assignment, selected during onboarding;
- `selectedWorld`: the prepared world currently browsed by the app;
- `authorityWorld`: the authority for one entity or operation;
- `sourceWorld`: provenance on a regional domain event only.

Onboarding recommends the nearest world, but the user explicitly makes the
initial selection after being told that the home world cannot be changed.
Changing `selectedWorld` never moves authority. Version 1 provides no
user-facing home migration; `epoch` is reserved for a future controlled
authority transfer.

`userHomes` is server-written routing state replicated to all worlds. The
signed Firebase Auth claim can cache the caller's own `homeWorld`; server-side
target routing uses the local `userHomes` mirror and a trusted fallback when
the mirror is missing. Client-supplied world values never establish authority.

**Decided for onboarding readiness:** the Asia bootstrap authority commits the
immutable home assignment and returns `accepted` without waiting for every
world. The app remains in onboarding only until the selected `homeWorld` has
acknowledged the routing revision and atomically applied the account state
required for normal use there. At that point the user may enter the app even
while other world mirrors are still being applied.

The home-assignment `globalOperation` nevertheless snapshots every active
world in `requiredWorlds` and remains `pending` until all of those mirrors
acknowledge. Outbox delivery, reconciliation, and alerts therefore continue
after the user starts using the app, and an unprepared non-home world is not
silently treated as synchronized. A world activated later is handled by that
world's activation backfill rather than being added to the existing operation.

**Decided for world entry:** version 1 does not perform on-demand mirror
creation during a world switch. The destination bootstrap worker applies the
local routing mirror and the minimum account projections in one destination
transaction; therefore an owner-readable `userHomes/{uid}` at the expected
`epoch` is the readiness marker and no separate readiness collection or field
is required. The app may change `selectedWorld` only when that marker exists
in the target database. Until then the world selector is disabled with a
preparing state, and a notification, invite, or deep link to that world shows
the same state without changing worlds.

Callable handlers and any remaining direct-write Rules reject stateful writes
with `world-not-ready` when the caller's local bootstrap marker is absent.
Trusted fallback to the Asia directory remains available for server-side
target-user routing and repair diagnostics, but it does not make an
unprepared world eligible for client entry. Outbox delivery and reconciliation
are the only normal paths that finish the missing bootstrap; switching worlds
does not initiate a second replication path.

Authority assignment by entity:

| Entity | Authority world |
| --- | --- |
| Profile, private settings, and FCM registry | User's `homeWorld` |
| Directed follow edge | Follower's `homeWorld` |
| Block edge | Blocker's `homeWorld` |
| Account-safety record | Subject user's `homeWorld` |
| Note, message, membership, and invite | Note's world |

`globalOperations/{operationId}` is stored in the same authority database as
the mutated entity. The operation document is both the client-visible status
record and the durable replication work item, so no separate
`globalOutbox/{eventId}` document is required for this path. The entity
mutation and operation acceptance commit atomically. The operation response
includes `authorityWorld`. Workflows that require durable client observation
persist `(authorityWorld, operationId)` for reconnection.

The client does not observe every global operation. Each initiating workflow
selects one of the client-observation policies below. This choice affects only
device-side progress reporting: the operation document remains the durable
server work item, and replication triggers and reconcilers continue regardless
of whether any client is listening.

### Client observation policy

| Policy | Use when | Initial operation groups | Client behavior |
| --- | --- | --- | --- |
| `none` | Neither the user nor an administrator needs durable per-operation progress | Profile and public-profile edits, follow/unfollow, language and notification preferences, entitlement replication, notification delivery, and server-originated automation | Validate the accepted response, but do not persist the operation reference or create a Firestore listener. Optimistic UI or the replicated domain state supplies any later visible result. |
| `durable` | The initiating user or administrator must be able to distinguish processing, delayed, and terminal states after navigation or app restart | Block/unblock and administrator-issued bans, posting restrictions, and other account-safety commands | Persist `(authorityWorld, operationId)`, listen through `GlobalOperationRepository`, restore pending listeners on app launch, and remove the remembered reference and listener at a terminal state. |

World readiness is not represented by a remembered operation listener. World
switching checks the target world's local readiness marker, which is the state
that actually authorizes access. Operational monitoring of server-originated
work uses backend metrics and administrator tooling rather than end-user
listeners.

The call site must select `none` or `durable` explicitly; operation type must
not acquire observation merely because its response happens to be `pending`.
There is no `sessionOnly` policy initially. A durable listener is app-scoped
rather than screen-scoped and survives navigation. Clients may read only their
own operation status and cannot write operation state. Since only pending
durable operations are listened to and terminal listeners are cancelled, the
normal listener count is zero or a small number. Do not add an arbitrary cap
unless measurements show sustained accumulation; any future cap must retain a
polling or app-resume recovery path rather than silently forgetting work.

No selected-world status projection is included initially; one may be added
later as a non-authoritative cache only if measured cross-region listener
latency justifies it.

## Design decisions

Decide these in dependency order because the earlier choices define primitives
used by the later operations:

| Order | Status | Decision | Primary question | Recommended starting point | Unblocks |
| --- | --- | --- | --- | --- | --- |
| 0 | Decided | Shared global-command contract | How are retries, revisions, completion, failures, authority, and observation represented? | Operation-as-work-item, immediate acceptance, selective durable client observation, reconciliation, retention, replay, and escalation thresholds are defined below | All replicated writes |
| 1 | Decided | Block completion semantics | When may block/unblock be reported as complete? | `complete` only after every required enforcement mirror acknowledges and the corresponding local cleanup intents are durable; cleanup execution remains a separate background phase | Follow, invite, note, message, like, and map enforcement |
| 2 | Decided | Account-safety authority | Where are moderation points, restrictions, and bans serialized? | Subject user's home-world `accountSafety/{uid}`, immutable regional violation events, and one enforcement mirror per active world | Cross-world posting restrictions and bans |
| 3 | Decided | Note-administrator invitation and routing | How is trusted note administration delegated and discovered across worlds? | Target-bound, single-use administrator invitation in the note world with a signed world hint; general private-note invitations are retired; managed notes are listed only in the selected world | Cross-world administrator delegation and removal of redundant member-invite paths |
| 4 | Decided | Storage placement | Which bucket owns each world's images and cleanup jobs? | One regional bucket per world, routed together with Firestore and Functions; the initial North America world remains in Iowa | Message/pin image moderation, deletion, and locality claims |
| 5 | Decided | Notification delivery ownership | Which worker is allowed to send each logical notification? | The source world owns regional-content notifications; the user's home world owns account/global notices | FCM outbox, token cleanup, and duplicate prevention |
| 6 | Decided | Moderation rejection lifecycle | Can hidden content be restored, and when is dormant content deleted? | Hide immediately, release quota once, retain for 30 days, then clean up; administrator restoration may temporarily exceed the creation limit | Retention jobs, appeals, Storage cleanup, and audit policy |

### 0. Shared global-command contract

Before selecting collection paths, define one envelope used by block, safety,
profile, social, and notification replication:

```text
operationId
operationType
entityId
revision
authorityWorld
ownerUid
payloadHash
status: pending | complete | failed
acceptedAt
worldCatalogVersion
requiredWorlds
worldAcks
createdAt
updatedAt
completedAt
failureCode
expireAt (terminal operations only)
```

`homeWorld` is the user's immutable home assignment, while
`authorityWorld` is the database coordinating this particular operation.
They are often equal for user-owned global data, but a note operation is
coordinated by the note's world and an account-safety operation by the subject
user's home.

The generic operation does not store the world from which the UI happened to
start the request; it has no effect on routing or consistency. When a regional
domain event must retain provenance, such as a moderation violation emitted by
note content, that source event uses the explicit field `sourceWorld`. This
field belongs to the event, not to every global operation.

**Decided for an extensible world catalog:** world membership is trusted,
versioned server configuration rather than an application enum fixed to three
entries. Each catalog entry supplies a stable `worldId`, `databaseId`,
Firestore location, Functions region, bucket name, display metadata, and
lifecycle state. Clients may fetch and cache the public active-world list, but
they submit only a `worldId`; trusted server routing resolves all resource
identifiers and rejects inactive or unknown worlds.

Each global operation snapshots both `worldCatalogVersion` and
`requiredWorlds` in its authority transaction. A world activated later is not
added retroactively to an already-pending operation. Before a new world may
become `active`, deployment must provision its database, indexes, Rules,
Functions, bucket, cleanup workers, and monitoring; backfill the current
profile, social, block, and account-safety mirrors; and reconcile to a recorded
high-water mark. Activation publishes a new catalog version only after those
guards pass. Operations accepted from that version onward require the new
world's acknowledgement.

Existing users retain their immutable `homeWorld`; adding a world does not
migrate accounts or regional content. The new world may be offered as a home
only to newly assigned users and as a selectable content world according to
product policy. Removing a world that still owns user authorities is a
different migration problem and is not implied by this expansion mechanism.

The decisions are:

- whether callers generate `operationId` or receive it before retrying
  (**decided:** the initiating caller generates it before the first request);
- the revision authority for each entity
  (**decided:** each independently replicated authoritative entity owns its
  revision);
- which failures remain retryable `pending` versus terminal `failed`
  (**decided:** `failed` is limited to deterministic rejection before the
  authority mutation; committed or uncertain mutations remain `pending` until
  required propagation completes);
- how long a callable waits before returning a pending operation
  (**decided:** every command returns `accepted` immediately after its
  authoritative mutation and operation work item commit; it never
  waits for destination acknowledgement);
- how clients poll or observe completion
  (**decided:** each initiating workflow explicitly selects `none` or
  `durable`; only `durable` uses an app-scoped `GlobalOperationRepository` to
  listen in the operation's `authorityWorld` and restore remembered pending
  IDs after navigation or app restart);
- event delivery and durable work representation
  (**decided:** the operation document itself is the durable work item; a
  separate global replication outbox document is not created);
- operation retention and replay behavior
  (**decided:** pending operations have no TTL, terminal operations expire
  after 30 days, and replay is server-only against the same operation);
- stale-pending warning and critical-alert thresholds
  (**decided:** reconcile after 10 minutes, warn after 15 minutes for
  safety-critical operations or one hour for ordinary operations, and raise a
  critical alert for any operation pending for 24 hours).

Recommended invariant: the same `operationId` with the same payload is
idempotent; reusing it with a different payload is rejected. Destination
mirrors apply only a strictly newer revision.

The client generates one lowercase UUID v7 operation ID for each logical user
action and retains it for retries until a terminal result is observed. The
UUID includes a random component while keeping the identifier convention used
by other client-created entities. The authority command binds the ID to the
authenticated caller, operation type, target entity, and a deterministic
payload hash. Repeating
that binding returns the existing operation; the same caller reusing the ID
with different input is rejected. Operation status is readable only by the
bound caller or a privileged server process, so a client-chosen ID does not
grant access to another user's operation. Server-originated commands follow
the same rule: the initiating producer generates the ID once and persists it
with its source event.

Each independently replicated authoritative entity owns a monotonically
increasing integer revision. Examples include one profile, one directed follow
edge, one block relationship, one account-safety record, and one independently
replicated settings document. The authority transaction updates the entity,
increments its revision, and creates the operation work item atomically.
Replaying an already committed `operationId` returns the recorded revision
without incrementing it again.

Destination mirrors apply an event only when its revision is strictly greater
than the stored revision. A logical deletion writes a revisioned tombstone
instead of immediately removing the authority record, so an older create or
update event cannot resurrect deleted state. There is no shared per-user or
project-wide revision counter.

`failed` means the authority mutation is known not to have committed and the
same authenticated request cannot succeed without changing its input or
preconditions. Examples are authorization failure, invalid input, a missing
target, a violated business precondition, an unsupported operation version,
or reuse of an operation ID with a different payload.

Transient infrastructure errors, throttling, an unknown authority commit
result, and incomplete destination acknowledgement remain `pending` and are
retried with the same operation ID. Once the authority mutation has committed,
propagation failure never changes the operation to `failed`; work that outlives
the platform event-delivery window remains logically pending and requires
repair or an explicit administrative resolution. This prevents a caller from
interpreting a partially applied mutation as a safe total failure.

The synchronous response communicates acceptance, not global completion.
Block/unblock and future administrator-issued safety commands follow the same
response contract as profiles, settings, and social commands. The UI may show
the returned current status without a fixed wait. An operation becomes
`complete` only when its declared required targets acknowledge it.

The authority transaction must create the operation document atomically with
the authoritative entity mutation before any response is returned. Work must
not rely on an unawaited promise continuing in the callable process after its
HTTP response.

A Cloud Functions v2 Firestore `onDocumentCreated` trigger is deployed for the
`globalOperations/{operationId}` path in each named database. It invokes one
idempotent replication worker, which reads the durable operation document,
applies the revision only to worlds that have not acknowledged it, and records
each acknowledgement on the operation. The same worker path is used for
duplicate event delivery, client retries, and scheduled repair; already
applied revisions become no-ops. Firestore events are at-least-once and
unordered, so correctness still depends on the operation ID and per-entity
revision guards.

The trigger is the low-latency delivery path, not the sole durable queue. A
scheduled reconciler queries old `pending` operation documents and invokes the
same worker, covering an expired or accidentally deleted platform event.
Cloud Tasks can be added later for per-target rate limiting or more explicit
retry control, but enqueueing a task is not part of the authority Firestore
transaction and therefore does not replace the operation document.

Notification-delivery and object-deletion outboxes remain separate. They
represent non-Firestore side effects such as FCM sends and Storage deletion,
whereas `globalOperations` represents application of revisioned Firestore
state in the required world databases.

Pending operations have no TTL. A terminal `complete` or pre-commit `failed`
operation receives `expireAt = terminalAt + 30 days` and can be removed by a
Firestore TTL policy. Replay is server-only and invokes the same idempotent
worker against the existing operation; it does not allocate another entity
revision.

Initial stale-pending policy:

| Pending age | Operation class | Action |
| --- | --- | --- |
| 10 minutes | All | Eligible for the scheduled reconciler, which runs every 15 minutes with a bounded batch |
| 15 minutes | Block, unblock, BAN, and posting restriction | Raise an operational warning |
| 1 hour | Ordinary global operation | Raise an operational warning |
| 24 hours | All | Raise a critical operational alert |

These are monitoring and repair thresholds, not additional operation states.
`attentionRequired` is derived from `status`, `acceptedAt`, `operationType`,
`requiredWorlds`, and `worldAcks`; it is not persisted on every operation.
An escalated operation remains logically `pending` and continues to be
eligible for idempotent repair. The client displays a delayed-processing
message rather than an error and makes clear that processing continues after
the user leaves the screen.

### 1. Block completion semantics

Decide what “blocked” means at the API boundary:

- **All-world completion:** return `complete` only after every world captured
  in the operation's `requiredWorlds` has acknowledged the block revision.
- **Authority-only completion:** mark the command complete after the authority
  write while
  other worlds may still allow interaction temporarily.

Recommended: use all-world completion for the backend guarantee. The client can
optimistically remove the other user immediately, while the durable operation
remains `pending` during a regional outage. Do not label the operation
`complete` until all mirrors acknowledge.

**Decided for block:** the authority write in the blocker's `homeWorld` commits
before the API returns `accepted`, and the client hides the blocked user
immediately. Each world begins enforcing the block when its local mirror
acknowledges the revision. A world whose mirror has not yet acknowledged may
briefly accept an interaction; ordinary regional actions do not perform a
cross-region authority fallback during this window. The operation remains
`pending` until every required mirror acknowledges and only then becomes
`complete`. This intentionally accepts a normally short replication gap in
exchange for keeping regional actions local and low-latency.

**Decided for unblock:** unblock uses the same all-world completion rule. Its
authority revision commits in the blocker's `homeWorld` before the API returns
`accepted`, while the client displays that the unblock is being propagated.
Each world stops enforcing the block only after its local mirror applies the
unblock revision. A world with an older mirror may therefore continue denying
the relationship temporarily. The unblock operation becomes `complete` only
after every snapshotted required world acknowledges it.

**Decided for unblock tombstones:** the authority keeps a minimal inactive
block-edge revision watermark until account deletion, preserving monotonic
revision allocation for a future re-block. Each world's enforcement mirror
keeps the unblock tombstone for 90 days after all-world completion and then
deletes it through TTL. Ninety days is a defense-in-depth retention window,
not a Firebase delivery requirement. It covers trigger configuration changes,
unexpected delivery delay, and operational mistakes at low storage cost.
Re-blocking increments the authority revision and removes the mirror TTL before
the new active state is applied.

**Decided for enforcement-mirror shape:** version 1 keeps the existing
directional path in every world instead of adding a canonical-pair collection:

```text
users/{blockerUid}/blockedUsers/{blockedUid}
  blockedUid
  isBlocked
  revision
  authorityWorld
  updatedAt
  expireAt  # inactive mirrors only
```

The blocker's `homeWorld` is the single authority for this direction. A local
interaction check reads the two possible directional documents in parallel
and treats only `isBlocked == true` as active; document existence alone is not
sufficient because an unblock tombstone remains for 90 days. A trusted local
query merges the caller's active outgoing and incoming relations once per app
session or world switch, and the app caches that peer set for content
filtering.

This deliberately favors single-writer simplicity over saving one local point
read per interaction. A canonical-pair mirror remains a later optimization
only if measured rule-read cost, map filtering, or callable latency justifies
the extra two-authority merge logic. It does not change the authority or
operation contract and can be introduced as a parallel projection before any
read path is switched.

The reconciler processes only `pending` operations. A destination revision
greater than or equal to an operation revision satisfies that operation's
acknowledgement without applying an older value. Privileged replay must also
compare the operation revision with the current authority revision and reject
a superseded operation. These rules prevent either recovery mechanism from
resurrecting an old block during the 90-day window or after a mirror tombstone
expires.

**Decided for follow edges:** accepting a block permanently removes both
directed follow edges. The edge owned by each follower is deleted through its
authority world, and derived follower/following counts converge from edge
truth. Unblocking does not recreate either edge. Before confirmation, the UI
must state that blocking removes both users' follow relationships and that
they are not restored by a later unblock.

**Decided for owned-note access:** cleanup is symmetric for notes owned by
either user. The blocked user loses membership and maintainer access to notes
owned by the blocker, and the blocker loses the same access to notes owned by
the blocked user. A creator is never removed from their own note. Membership
and maintainer access are not restored by unblocking. Notes owned by a third
party keep both membership records; local block enforcement provides mutual
content filtering and rejects direct interactions without arbitrarily
removing one participant. The block confirmation UI discloses the permanent
owned-note access removal.

**Decided for public and third-party-owned content:** block filtering is a
product/UI guarantee rather than a confidentiality boundary for content that
the viewer is otherwise authorized to read. The app loads the active local
block-peer set once at app scope and filters messages and other user-derived
items in memory; it does not perform a relationship read per content item.
Raw access to otherwise public or shared content through a modified client is
not prevented solely because of a block. Private-note authorization and every
direct interaction remain server- or Rules-enforced through the local block
mirror.

**Decided for scheduled messages:** cleanup symmetrically cancels each user's
unpublished scheduled messages in notes owned by the other user. The local
Firestore transaction deletes each reservation and releases its message slot
exactly once. Associated unpublished Storage objects are removed through a
durable, idempotent deletion job. Neither the message nor its reservation is
restored by unblocking. Already published and optimistic public-pending
messages are not part of this destructive cleanup; normal block filtering
controls their visibility.

**Decided for block completion versus cleanup:** the block operation becomes
`complete` when every snapshotted required world acknowledges an active
enforcement mirror.
Applying a mirror and creating or upserting that world's required cleanup
job intents occur in the same local transaction. Consequently, global
completion guarantees that block enforcement is active everywhere and that no
required cleanup work has been lost; it does not wait for the cleanup workers
to finish deleting follow edges, membership, maintainer access, scheduled
messages, or obsolete Storage objects.

Physical cleanup is not part of the user-visible block operation status. The
client may report the block as complete as soon as the enforcement guarantee
holds. Cleanup status and lag are visible to operational tooling instead. A
cleanup failure never reopens the completed block operation because the
enforcement mirrors already provide the safety boundary; it keeps the local
cleanup job eligible for repair and raises an operational alert.

#### Shared cleanup execution layer

Cleanup is a cross-cutting implementation concern rather than a block-specific
function. Block, invite, moderation, account deletion, expired tombstone, and
other mirrored-entity workflows may all need durable follow-up work. They use
one local job contract and runner infrastructure while keeping resource-
specific handlers and deployments separate.

Each target world owns its cleanup jobs. Cleanup jobs are not themselves
globally mirrored: the global operation or source outbox creates one
deterministically identified intent in every world that has local work.
Separate subcollections make Firestore and Storage jobs independently
triggerable and configurable:

```text
cleanupQueues/firestore/jobs/{jobId}
cleanupQueues/storage/jobs/{jobId}

  jobType
  sourceOperationId
  entityType
  entityId
  revision
  world
  status: pending | running | complete
  cursor
  attemptCount
  leaseUntil
  nextAttemptAt
  lastErrorCode
  createdAt
  updatedAt
  completedAt
  expireAt  # complete jobs only
```

The job ID is derived from
`(sourceOperationId, world, queue, jobType[, partition])`. Repeated source
delivery therefore upserts the same work instead of multiplying it. The
`revision` prevents a stale cleanup request from undoing newer entity state.
Leases, attempts, and cursors belong on these queue documents because they
control worker execution; unlike moderation audit metadata, they are not added
to `places` or `messages`.

The event-driven Firestore cleanup runner claims a short lease in a
transaction, dispatches by `jobType`, performs a bounded batch, persists its
cursor, and continues until complete. Initial handlers include block follow,
owned-note membership and maintainer cleanup, scheduled-message cancellation,
invite revocation, moderation-retention deletion, and account-data cleanup.
Every handler must be idempotent and must re-check the relevant entity
revision or terminal condition before deleting data.

The Storage cleanup runner is a separate deployed function. A Firestore
handler may transactionally enqueue a Storage job when it removes the final
reference to an object. Storage deletion treats `not found` as success and
never guesses an object path from untrusted client input. Keeping Storage work
separate prevents slow object operations and Storage IAM from consuming the
Firestore worker's concurrency or permissions.

Implementations share the job parser and validator, lease acquisition,
retry/backoff rules, cursor/checkpoint utilities, structured logging, metrics,
and handler registry. The individual handlers remain small and
resource-specific. Deploy separate Firestore and Storage workers for each
world so that they are colocated with the target resources and can have
different concurrency, memory, timeout, and IAM settings. This separation is
primarily for scaling and failure isolation; common code supplies the
implementation reuse.

A scheduled reconciler in each world scans old `pending` jobs and expired
`running` leases, then invokes the same runner used by the event-driven fast
path. `pending` and recoverable `running` jobs have no TTL. Completed jobs may
receive a short operational retention TTL after all checkpoints are durable.
Age and repeated-attempt thresholds produce alerts without turning a
recoverable job into a permanently failed cleanup state.

### 2. Account-safety authority

Decide whether moderation points and posting restrictions are global or
per-world. A per-world model permits a restricted user to switch worlds, so the
recommended state is globally enforced but serialized in the subject user's
`homeWorld`:

```text
accountSafety/{uid}
  revision
  violationPoints
  lastViolationAt
  nextPointDecayAt
  automatedRestrictedUntil
  automatedBannedUntil
  adminRestrictedUntil
  adminBannedUntil
  restrictedUntil
  bannedUntil
  isPermanentlyBanned
  authorityWorld
  updatedAt
```

`restrictedUntil` and `bannedUntil` are the effective local-enforcement
timestamps: each is the later of its automated and administrator source
fields. Keeping the sources separate is what makes override independence
implementable. Clearing an administrator override therefore reveals any
still-active automated period instead of accidentally clearing it, and a new
automated event cannot replace a longer administrator period.

Each content world writes an immutable, deduplicated violation event. One
transaction in the subject user's `homeWorld` applies it, then propagates the
resulting enforcement state in all world mirrors.

**Decided for enforcement scope:** moderation points, posting restrictions,
and bans are global account-safety state rather than per-world state. The
subject user's immutable `homeWorld` owns `accountSafety/{uid}` and serializes
all updates. Asia, Europe, and North America each keep a revisioned enforcement
mirror in the initial catalog; every subsequently activated world must have the
same current mirror before users can select it, so switching worlds cannot
bypass a restriction or ban.

**Decided for rejected-content timing:** once the moderation provider returns
a rejecting verdict, the content world hides the item immediately in its local
finalization transaction. It does not wait for the violation event to reach the
user's `homeWorld`, for points to be recalculated, or for a resulting
restriction to propagate globally. The same transaction durably records the
deduplicated violation-event intent; account-safety processing and mirror
application then continue asynchronously. This decision concerns the moment
of rejection: optimistically public content may remain visible while its
moderation action is still `pending`.

**Decided for restriction and ban completion:** a new posting restriction or
ban uses the same all-world acknowledgement rule as a block. The user's
`homeWorld` first commits the authoritative account-safety revision and its
global operation, after which the API may report `accepted`. Each world starts
enforcing the revision when its local mirror applies it. The operation remains
`pending` until every world in its `requiredWorlds` snapshot acknowledges that
revision, and only then becomes `complete`. A regional outage therefore delays
formal completion but never rolls back enforcement already applied
elsewhere.

**Decided for point expiry:** violation points gradually decay after a period
without new violations. They are neither permanent nor reset wholesale when a
temporary restriction or ban expires. The authority applies decay lazily in
the next account-safety transaction by comparing the stored point-update time
with server time, then adds the new event's points. No scheduled scan or
periodic write across all users is required. Restrictions and bans continue to
use their absolute `restrictedUntil` and `bannedUntil` timestamps, so an
unchanged mirror can determine locally when a temporary enforcement period has
ended.

**Decided for decay cadence:** points remain unchanged for 30 complete days
after the most recent point-bearing violation. The first six-point decrement
becomes due after the following seven complete days, and another six points
become due for each additional complete seven-day interval. A new
point-bearing violation first applies every due decrement, then adds its points
and restarts the 30-day grace period. The authority stores
`nextPointDecayAt` so repeated lazy calculations cannot apply the same
decrement twice; once the total reaches zero, it clears that timestamp. This
reduces the 100-point ban threshold to zero after roughly five
violation-free months without periodic Firestore jobs.

**Decided for point scale and automated actions:** account safety uses a
zero-to-100 integer scale, capped at 100 for the current enforcement score:

| Safety result | Points |
| --- | ---: |
| `sensitive` label | 0 |
| Automated `review` recommendation | 0 |
| Automated high-confidence `hidden` decision | 25 |
| Administrator changes a reviewed item to `hidden` | 25, unless that content already produced its 25-point hidden event |

Warning begins at 20 points, a temporary posting restriction begins at 60
points, and a temporary ban begins at 100 points. These rounded values preserve
the current behavior: one confirmed hidden item produces a warning, three
produce a restriction, and four produce a ban. Content-scoped deterministic
event IDs prevent an automated hidden decision and its later administrator
confirmation from charging the same 25 points twice. Sensitive labels and
unconfirmed review recommendations affect presentation or the review queue,
not account punishment. The immutable event history may record violations
beyond the capped score even though the current enforcement score remains 100.

**Decided for enforcement duration:** a posting restriction lasts 24 hours and
a temporary ban lasts seven days. These are fixed initial durations rather
than escalating by recurrence. A later point-bearing violation may start a new
period from that event when the applicable threshold is still met; it does not
extend a period merely because a background retry redelivers the same
deduplicated event. The authority stores absolute server timestamps and the
world mirrors enforce them by comparing against server-derived current time.

**Decided for operation scope:** a posting restriction and a temporary ban are
different enforcement levels:

| Operation family | Posting restriction | Temporary ban |
| --- | --- | --- |
| Read maps, notes, messages, profiles, and notices | Allow | Allow |
| Create or edit notes, messages, scheduled messages, or content images | Deny | Deny |
| Create likes, follows, invitations, memberships, maintainer grants, or visit records | Allow | Deny |
| Remove own content, cancel scheduled work, unlike, unfollow, leave, or revoke an invite/access grant | Allow | Allow |
| Block/unblock, report content or users, appeal, sign out, or delete the account | Allow | Allow |
| Private preferences and other non-public account maintenance | Allow | Allow |

Creating a relationship and removing one are intentionally asymmetric during
a ban: the user cannot create new participation, but may reduce their
visibility, access, or relationships. All affected callable and trusted
background write paths consult the target world's local account-safety mirror;
they do not call the `homeWorld` in the hot path. A timestamp that has expired
is treated as inactive even if a cleanup job has not yet cleared the field.
Any client-direct write path for a denied operation must either move behind a
callable or enforce the same mirror check in Firestore Rules.

**Decided for administrator access:** administrators may increase or decrease
the score and may impose, change, or clear posting restrictions and bans from
the existing in-app moderation area. The Flutter screen is only a presentation
gate; every command calls a trusted `adminUpdateAccountSafety` endpoint that
requires the Firebase Auth `admin: true` custom claim. Firestore Rules deny
client writes to the authority, enforcement mirrors, global operations, and
audit records.

The command requires a client-generated operation ID, target UID, typed action,
reason, and optional moderation-review or support-case reference. It resolves
the target's immutable `homeWorld`, then atomically writes the authoritative
revision, immutable administrator audit event, and `globalOperations` work
item. The app displays `accepted` immediately and observes the operation until
every required enforcement mirror acknowledges `complete`; navigation does
not cancel processing. The administration screen also shows current score,
effective restriction/BAN expiry, authority world, propagation state, and
recent audit history. Existing content-review actions emit their account-
safety events through the same authority pipeline rather than directly
mutating a regional user document.

**Decided for override independence:** manually setting, changing, or clearing
a posting restriction or ban does not implicitly change `violationPoints` or
its decay schedule. Likewise, a point adjustment does not silently clear an
explicit administrator restriction or ban. The administration UI presents
these as separate actions, each with its own confirmation, reason, idempotency
key, authority revision, and audit event. This permits an emergency action
unrelated to content points and permits an appeal to remove enforcement
without erasing the underlying history.

**Decided for administrator duration presets:** the administration UI offers
posting restrictions of 24 hours, three days, or seven days, and bans of seven
days, 30 days, or permanent. The server accepts only these typed presets rather
than an arbitrary client timestamp and derives every temporary expiry from
server time. A permanent ban sets `isPermanentlyBanned: true` instead of using
a far-future `bannedUntil`; clearing or replacing it requires a separate
audited administrator action. The normal automated thresholds continue to use
the fixed 24-hour restriction and seven-day temporary ban.

**Decided for event retention and reconciliation:** source violation events,
authority application receipts, automated moderation audit events, and
administrator account-safety audit events are retained for one year. These
records contain identifiers, decisions, points, actor/reason metadata, and
timestamps, but not submitted text, image bytes, or copied content payloads.
They remain in the one source or authority world that owns them and are not
triplicated with the enforcement mirrors. Fields that are never queried receive
single-field index exemptions to limit index storage.

Every event has a deterministic ID. The authority transaction creates an
application receipt, applies any due point decay, changes the score or
enforcement state, increments the authority revision, and creates the global
operation exactly once. A duplicate event finds its receipt and returns the
original result without applying points again. Authority application time is
the point-bearing time, so recovery after an outage remains serializable and
does not require recomputing non-commutative decay from out-of-order source
timestamps.

A low-frequency reconciler retries nonterminal source operations and verifies
that the authority receipt and resulting revision exist. Missing work is
redelivered with the same event ID; completed authority state is never rebuilt
by blindly summing events. The authority document and its revision are the
current checkpoint used to repair enforcement mirrors.

An event or receipt receives `expireAt = createdAt + 365 days` only after its
source operation is terminal, its authority receipt exists, and the relevant
authority revision is included in the checkpoint. An audit event receives the
same one-year TTL after its transaction commits. Stuck or unverified records
omit `expireAt` and remain visible to operational alerts. TTL deletion is an
eventual storage lifecycle action, not part of operation completion.

Keep this state separate from the general replicated `users/{uid}` document so
ordinary profile updates cannot overwrite a safety revision.

### 3. Note-administrator invitation and routing

Distinguish privilege delegation from ordinary participation. Internally the
role may remain `maintainer` or “remote operator,” but user-facing copy calls it
**note administrator** and uses actions such as “Add an administrator” and
“Help manage this note.” Do not expose “remote operator” as a product term.

**Decided for remote scope:** a note administrator may read the full note and
perform authorized administration from any location. Ordinary messages, likes,
and visit records remain subject to the same location requirement as every
other user; administrator status is not a remote participation exemption.
Remote administration does not create a visit record.

**Decided for delegation:** both the creator and an active note administrator
may invite another specific user to become a note administrator. The invitation
is target-UID-bound, single-use, expiring, and records `invitedBy` so delegation
chains remain auditable. Forwarding the link cannot grant authority to a
different account. The creator remains the immutable owner, cannot be removed,
and retains ultimate recovery authority.

**Decided for flat administrator authority:** every active note administrator
has the same delegation and revocation powers. Any administrator may cancel any
pending administrator invitation and remove any other administrator except the
creator. There is no inviter hierarchy, descendant cascade, or peer rank.
Removal commits in the note world, takes effect for subsequent reads and
administration immediately, and records actor, target, reason, and timestamp in
an immutable audit event. The removed user may still access the note through
the ordinary location/password rules but no longer has remote-administration
access. An administrator may also resign through a separate self-removal
action; the creator cannot resign without a future ownership-transfer feature.

The administrator invitation is authoritative in the note world. A signed
token contains a version and world hint plus an unguessable nonce, allowing the
app to validate a preview in the correct world without a global
`inviteRoutes` directory. Opening the link does not change the selected world.
The app explains the permissions and target world, asks for confirmation,
and first verifies that the caller's bootstrap marker exists in that world.
If the world is still preparing, the preview remains visible but acceptance
and world switching are disabled; accepting the invitation does not initiate
on-demand replication. Once prepared, the app accepts the invitation
transactionally in the target world and changes the selected world only after
success and explicit consent. `homeWorld` never changes.

**Decided for ordinary private-note access:** retire general member
invitations and the reusable bearer-link flow. A shared password remains the
ordinary private-access mechanism, while invitation is reserved for explicit
note-administrator delegation. This avoids two overlapping shared-secret
mechanisms and avoids making remote group participation a primary product
concept. A future target-bound member invitation may be introduced only if
measured demand for individually revocable private groups justifies it.

**Decided for invitation lifetime and limits:** an administrator invitation is
valid for seven days. Each `(placeId, targetUid)` has at most one pending
invitation, represented by a deterministic identity and updated revision/token
when reissued after expiry or revocation. A note may have at most 10 pending
administrator invitations and 10 active administrators excluding the creator.
These are abuse and accident circuit breakers rather than intended product
limits.

Invitation creation and terminal transitions update an exact
`pendingAdministratorInviteCount` in the same note-world transaction.
Acceptance also checks and increments the active-administrator count
atomically, so concurrent acceptances cannot cross the limit. An expired
invitation is rejected immediately from server time even before physical
deletion. A typed local cleanup job transitions expired pending records and
releases their pending slot exactly once; Firestore TTL may remove the terminal
record later but does not own counter correctness.

**Decided for administrator discovery:** the management list queries only the
currently selected world, for example with
`places.where(maintainerIds, array-contains: uid)`. It does not federate three
queries and does not maintain a home-world or all-world managed-note
projection. To manage a note in another world, the user deliberately switches
to that world. Cross-world administrator invitations are expected to be rare;
the home-world notification and signed invitation link provide the initial
route and identify the target world. This keeps ordinary home-world use local
and makes administrator discovery consistent with the MMO-style world model.

### 4. Storage placement

Define each world as one routing bundle:

```text
worldId -> databaseId -> Firestore location -> Functions region -> bucket
```

Recommended: one bucket per world, colocated as closely as supported with that
world’s Firestore and Functions. Store a world-relative object path in content
documents and infer the bucket from the trusted world route rather than
persisting arbitrary bucket URLs.

**Decided for bucket ownership:** every active world owns one regional Cloud
Storage for Firebase bucket. Initially those worlds are Asia, Europe, and North
America. Note pin images, message images, moderation candidates, and cleanup
jobs stay in the same world bundle as their Firestore authority and Functions
workers. No world treats the Tokyo bucket as an image authority and no content
image is replicated merely to make it global.

**Decided for global image scope:** the application owns no global image
objects. Note pin images and message images remain only in their content world.
An OAuth or Firebase Authentication `photoUrl` may continue to reference the
identity provider's external URL; the application does not copy that image into
its regional buckets. If user-uploaded avatars are introduced later, their
ownership and replication policy will be decided as a separate feature rather
than being implied by this content-image design.

The trusted world registry maps `worldId` to the database, Functions region,
and bucket name. Firestore documents store a world-relative object path, not a
client-supplied bucket name, `gs://` URL, or download URL. Client and server
code select the configured bucket from `worldId`; current server calls that
implicitly use `getStorage().bucket()` must be made world-aware before the
additional buckets are enabled.

**Decided for initial regional colocation:** use the following initial storage
and compute placement:

| World | Firestore location | Functions region | Bucket | Bucket location |
| --- | --- | --- | --- | --- |
| `asia` | `asia-northeast1` (Tokyo) | `asia-northeast1` | `world-notes-prod.firebasestorage.app` | `asia-northeast1` |
| `northAmerica` | `us-central1` (Iowa) | `us-central1` | `world-notes-prod-north-america` | `us-central1` |
| `europe` | `europe-west1` (Belgium) | `europe-west1` | `world-notes-prod-europe` | `europe-west1` |

North America remains one `northAmerica` world in Iowa for the initial
deployment. The catalog is nevertheless cardinality-independent: a later
`northAmericaWest`, Southeast Asia, Oceania, or other world is added through
the same provisioning, mirror-backfill, and catalog-activation protocol rather
than by adding another hard-coded branch.

Actual globally unique bucket names are deployment configuration, not domain
data. The current default bucket's immutable location was verified as Tokyo.
The North America and Europe buckets were created in their corresponding
Firestore regions and linked to Firebase Storage.

**Decided for image access:** clients do not rely on Storage Rules consulting a
content document in a named Firestore database. They request image access from
a trusted Function in the content world. The Function authenticates the caller,
checks the authoritative local content, moderation, and private-note access
state, and returns a short-lived signed URL. Cloud Storage serves the image
bytes directly; Functions do not proxy the object body. The client caches both
the signed URL and downloaded image, and a batch endpoint may issue URLs for
the visible image set to avoid one Function round trip per image.

When content becomes hidden, its Firestore visibility changes immediately.
The image-access Function then refuses every new signed-URL request and the app
stops rendering both its URL and locally cached bytes. A URL issued before the
transition may remain usable until its 24-hour expiry, which is the accepted
revocation bound for optimistic moderation. The object and its restorable
content remain for the 30-day moderation appeal window; a durable cleanup job
removes them only after that retention period. Ordinary user deletion,
replacement of an approved image, and abandoned uploads may enqueue earlier
deletion because they have no moderation-restoration requirement. Object paths
are immutable and never reused, so a previously issued URL cannot expose a
replacement image.

**Decided for signed-URL lifetime and caching:** a download URL is valid for 24
hours. Image responses use a private client-cache policy with a corresponding
maximum age; shared caches must not retain the signed URL or response. The app
must stop rendering cached bytes as soon as authoritative content state becomes
inaccessible, and may request a fresh URL after expiry only by repeating
authorization. Signed query strings are redacted from logs, analytics, and
error reports. The 24-hour limit bounds access through a leaked or previously
authorized URL after an access-state transition. For moderation hiding it is
the deliberate revocation bound while the raw object remains restorable; for
permanent deletion it is also a fallback if durable cleanup is delayed.

**Decided for upload paths:** clients upload each immutable image directly to
its final world-relative object path. There is no quarantine-to-final copy or
move. Before an authoritative Firestore content document references that exact
path, the image-access Function refuses to issue a signed URL. A public-pending
message or pin candidate references and serves the same final object. Rejection
hides the reference from application reads and prevents new signed URLs, while
retaining the object for 30 days. Uploads that never become referenced remain
inaccessible and are removed by the regional orphan sweeper after a grace
period.

**Decided for deletion completion:** a Storage deletion job does not transition
to a terminal failure merely because it exceeds an attempt count. It remains
durable and retryable until deletion succeeds or the object is already absent,
which is also success. Retries use `nextAttemptAt` with bounded exponential
backoff and jitter so a persistent IAM, configuration, or service failure does
not create a hot loop. Pending jobs have no TTL. Age and repeated failures
raise operational alerts without stopping reconciliation; after the underlying
problem is fixed, the same deterministic job resumes automatically.

**Decided for deletion retry timing:** the event-driven runner attempts
deletion immediately. Subsequent due times are approximately 10 minutes, 30
minutes, 2 hours, and 6 hours after successive failures, with jitter; persistent
failures are retried every 24 hours thereafter. A per-world reconciler runs
every 10 minutes and claims due jobs or expired leases. A job still incomplete
after 1 hour raises a warning and after 24 hours raises a critical alert. These
alerts do not change the job's retryable status.

**Decided for completed deletion-job retention:** after successful deletion,
the job records `complete`, `completedAt`, and an `expireAt` 30 days later.
Firestore TTL removes the small job record after that period. This matches the
terminal `globalOperations` retention window and preserves enough history for
late duplicate suppression and operational investigation without retaining the
deleted image.

**Decided for orphan-upload tracking:** each regional bucket's object-finalize
event upserts a small `imageUploads/{uploadId}` record in the corresponding
world database. Its deterministic ID is derived from the immutable object path;
the record includes the observed Storage generation, owner, content kind,
upload time, and `checkAfter` 24 hours later. The content-acceptance transaction
upserts that same record as referenced by the authoritative content path, so
event-delivery order does not create a gap. A concurrent sweeper decision and
content attachment contend on the same document and therefore cannot both
commit from an unreferenced state.

An hourly regional sweeper queries only due, unreferenced upload records rather
than listing the whole bucket. It re-checks the authoritative content reference
and generation immediately before creating the idempotent Storage deletion
job. The deletion runner checks the guard again and uses the recorded object
generation as a precondition, preventing a stale job from deleting a newer
object. Referenced tracker records and completed orphan records receive a
30-day TTL after their terminal state. A low-frequency, sharded bucket
inventory audit remains a repair mechanism for a permanently missing finalize
event, not the normal cleanup path.

**Decided for moderation data locality:** each content world's moderation
worker reads image bytes from that world's colocated bucket and holds them only
in memory for evaluation. The application does not copy candidate images to
Tokyo, to a shared moderation bucket, or to any other application region.
Transmission from the regional worker to the selected external moderation
provider remains a distinct provider and data-residency concern.

### 5. Notification delivery ownership

Exactly-once FCM delivery is not available, so choose one deterministic owner
and implement at-least-once delivery with application-level deduplication.

Recommended ownership:

- regional note/message events: the source world worker;
- account, safety, or developer notices: the recipient user's home-world
  worker.

The source transaction writes an outbox event with a globally unique event ID.
The owner reads the home-world authority for FCM tokens/preferences, re-checks
block/safety state, and sends. Regional message content does not need to be
copied into every world database.

**Decided for delivery ownership:** a regional note or message notification is
owned and sent by the content's source-world worker. It keeps the authoritative
content, moderation state, local enforcement mirrors, outbox, and delivery
status together. At delivery time it resolves each recipient's `homeWorld`,
reads that home database's preferences and FCM tokens, and sends through FCM;
those small credentials are not persisted in the source database. A temporary
home-world or FCM failure leaves the source outbox retryable and never delays
the original content operation. Account-safety, developer, and other
account-global notices are instead owned by the recipient's home-world worker.

**Decided for notification authority paths:** notification preferences and FCM
registration tokens exist only in the user's immutable `homeWorld`:

```text
users/{uid}/notificationSettings/main
users/{uid}/fcmTokens/{tokenHash}
```

`notificationSettings` is a collection, so the singleton `main` document
cannot be omitted; Firestore paths alternate collection and document segments.
The owner may read `main` through home-world Rules, while only trusted callables
may update it. FCM token documents are server-only delivery credentials and are
not client-readable. Neither subtree is replicated into selected content
worlds. Switching the selected world therefore does not move notification
authority or create another token registry.

**Decided for event deduplication and retention:** the source transaction
allocates a globally unique `eventId`, and recipient-level delivery state uses
that ID so duplicate trigger delivery and worker restart resume or no-op rather
than intentionally send again. Pending notification events have no TTL.
Terminal `complete`, `skipped`, or expired events retain their event and
recipient results for 30 days, then Firestore TTL removes them. This matches the
terminal retention used by `globalOperations` and cleanup jobs.

**Decided for notification retry and expiry:** delivery is retried with jittered
backoff at approximately immediate, 1 minute, 5 minutes, 30 minutes, 2 hours,
and 6 hours, followed by a final due attempt within the event lifetime. Normal
message, account-safety, and developer push events expire 24 hours after
creation. A note-administrator invitation push may retry only until the
underlying invitation's seven-day expiry. Expiry transitions the push event to
terminal `expired`; the authoritative account state, invitation, or in-app
notice remains available and no stale push is sent later.

Per-token FCM results are classified before retry. A
`registration-token-not-registered` (or the corresponding unregistered
registration result) means a formerly valid app registration is no longer
known to FCM and its home-world token record is deleted idempotently.
`invalid-registration-token` means the stored target value is malformed or is
not an FCM registration; it is also deleted after the server has separately
validated that the notification payload itself is valid. Transient FCM,
network, and rate errors retain the token and retry within the event lifetime.
Credential, sender-project, package, or provider-authentication errors are
treated as deployment faults and alert operators rather than deleting user
tokens.

**Decided for the moderation gate:** optimistic public content does not produce
a push while its `moderationAction` is `pending`. The source-world moderation
finalization transaction creates the notification outbox only when the verdict
is a visible terminal action (`allow`, `sensitive`, or `review`). A `hidden`
verdict creates no notification intent. Push is therefore an asynchronous
post-moderation side effect even though the content itself may be visible
optimistically before the verdict.

For an online device, healthy provider, warm workers, and no backlog, the
engineering estimate from content acceptance to FCM acceptance is roughly
2–10 seconds for text-only content and 4–20 seconds when image moderation is
required. Cold starts may add several seconds. FCM acceptance is not proof of
device display; offline state, Android Doze/priority, APNs, notification
permissions, and operating-system policy may delay or suppress the final
display. User-visible message notifications should use the platform's
high-priority alert delivery and an FCM/APNs lifetime matching the outbox
event's remaining lifetime.

**Decided for block races:** immediately before each FCM delivery batch, the
source-world worker re-reads that world's enforcement mirrors for both block
directions and re-checks that the source content and note remain visible. A
blocked recipient becomes terminal `skipped` for that event. This does not add
cross-region authority reads to ordinary notification delivery. Once a block
operation is `complete`, every required world has acknowledged its enforcement
mirror and subsequent notification attempts are therefore suppressed.

The accepted tradeoff is the irreducible in-flight window while a newly
accepted block is still `pending`: if the source-world mirror has not yet been
updated, or FCM already accepted the message, one notification can still
arrive. The client hides blocked content immediately after block acceptance,
and no attempt is made to recall a push already accepted by FCM.

### 6. Moderation rejection lifecycle

Optimistic publication makes rejection an aggregate-state transition rather
than an immediate recursive delete.

Recommended: hide/close locally first, release quota exactly once, retain the
review/audit material for an explicitly chosen period, and delete content
through a durable cleanup job afterward. If restoration is supported, it must
reserve a slot transactionally before making the note visible again.

**Decided for automated rejection:** an automated `hidden` decision is
administrator-restorable. The item becomes immediately invisible to ordinary
users but remains available through the administrator moderation workflow
during its retention window. An administrator may change the decision to
`allow` or `sensitive`; ordinary users cannot restore it. This preserves the
existing administrator-review capability and provides recovery from provider
false positives.

**Decided for hidden-content retention:** retain a hidden note or message, its
restorable child data, and its referenced image objects for 30 days from the
latest transition to `hidden`. It is invisible to ordinary users throughout
that interval and accessible only to the administrator moderation workflow.
After the deadline, durable cleanup jobs permanently delete the content tree
and regional Storage objects; restoration is no longer available. This aligns
the review window with the existing 30-day terminal retention used for
notification events and cleanup jobs. The current immediate deletion of
message images after an administrator hides a message must move to this
retention cleanup path so a restoration within the window is complete.

**Decided for post-deletion evidence:** after content cleanup, retain only
moderation metadata in `moderationAuditLogs`; do not retain the raw text, text
excerpt, image bytes, or image path. The evidence record contains the world,
target type and ID, subject UID, automated and administrator actions,
`moderationPolicyVersion`, evaluation and decision timestamps, administrator
UID and reason when applicable, `hiddenAt`, `purgedAt`, and a keyed
`contentFingerprint`. The fingerprint is an HMAC produced with a
server-controlled secret rather than a plain hash, so short candidate text
cannot be cheaply guessed from a Firestore leak. It supports equality
verification only and is not exposed to clients.

**Decided for audit retention:** retain each metadata-only
`moderationAuditLogs` record for one year, then delete it through Firestore
TTL. This covers the approximately five-month account-safety point decay
window and leaves additional time for administrator investigation without
retaining personal identifiers indefinitely. Raw content and images still
follow the shorter 30-day hidden-content retention and are never copied into
the audit record.

**Decided for quota release:** the transaction that first transitions an
active note to `moderationAction: hidden` immediately releases its per-world
active-note slot. The creator's local `noteStates/{placeId}` record tracks
whether that note currently holds a slot; only a `true` to `false` transition
decrements `activeNoteCount`. Duplicate provider delivery, administrator
actions, archival, and cleanup therefore cannot release the same slot twice.
The safety-point, posting-restriction, and ban system handles repeated rejected
creation rather than retaining hidden notes as an additional quota penalty.

**Decided for restoration quota:** an administrator restoration atomically
changes the note to a visible moderation action, changes its local slot state
from unheld to held, and increments the exact per-world `activeNoteCount`.
Unlike ordinary `createNote`, this trusted recovery operation may increment
the count beyond the user's 20/200 creation limit. The user cannot create
another note in that world until archival or another lifecycle transition
brings the count below the limit. Restoration never archives another note
automatically and does not introduce a separate quota-waiting state.

## Confirmed engineering risks independent of the initial world count

These already exist or become more visible under the new architecture:

- The current `createInviteLink` has a concurrent-create race, but the target
  design retires this endpoint instead of repairing that reusable-token model.
- `aggregatePublishedMessages` processes at most 100 items per minute and can
  accumulate an unbounded backlog during bursts.
- FCM sends and several Storage deletions occur after the Firestore commit
  without a durable outbox/cleanup queue.
- Note, message-like, visitor, follower, and message-count aggregates can
  hotspot a popular document.
- Moderation report resolution needs a world-aware full target identity.
- Every current function and the Flutter Firestore provider implicitly target
  the default database.

## Measurement plan

Before treating the estimates as SLOs, emit structured traces for:

- callable ingress to first database request;
- Firestore transaction duration and retry count;
- external moderation and Storage duration;
- authority command duration;
- each required-world mirror acknowledgement and the operation's catalog
  version;
- global-operation age and outstanding-world count;
- scheduler backlog size and oldest item age;
- map-pin base-query, block-filter, and enrichment duration;
- cold-start indicator and function region.

Recommended initial SLO candidates:

| Path | Candidate SLO |
| --- | --- |
| Regional non-moderated callable | p95 under 800 ms warm |
| Map-pin listing | p95 under 1.5 s warm |
| Text moderation publication | p95 under 4 s warm |
| Image moderation publication | p95 under 8 s warm |
| Global profile/settings mutation | p95 under 1.2 s warm |
| Global block/unblock logical completion | p95 under 2 s warm when all worlds are healthy |
| Normal global mirror propagation | p95 under 5 s |
| Social aggregate propagation | p95 under 30 s |
| Block physical cleanup | p95 under 5 minutes |
