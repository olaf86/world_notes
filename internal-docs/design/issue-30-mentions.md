# Issue #30 — Mention re-engagement loop

## Product contract

- A published message may mention up to three distinct participants.
- A participant is a user who has had at least one message become publicly
  visible in the note. Deleting or hiding a later message does not remove that
  historical participation record.
- Footprint-only visitors are never included.
- Mentions are selected as structured recipients; free-form `@name` text is
  not parsed.
- Choosing **Mention and reply** on another user's message opens the existing
  composer with that author preselected. This is a directed reply shortcut,
  not a threaded or quoted reply, so no `replyToMessageId` is stored.
- Mentioned messages cannot be scheduled. Selecting a mention resets the
  composer to **Publish now** and disables scheduling.
- Every valid mention creates a durable in-app notice. Push delivery is a
  separate, explicit `mentionsEnabled` preference and defaults off.
- Push and notice previews do not include message content.
- Opening either notification surface focuses the note's pin on the map. It
  never bypasses proximity access. Once the user is close enough and the
  server validates access, the note opens and highlights the target message.

## Firestore model

Server-owned participant projection:

```text
places/{placeId}/participants/{uid}
  userId: string
  displayName: string
  displayNameSearchKey: string
  searchBigrams: string[]
  photoUrl: string|null
  firstParticipatedAt: timestamp
  lastParticipatedAt: timestamp
  updatedAt: timestamp
```

The projection is created or monotonically refreshed only when moderation and
publication have both completed. It is not decremented when messages are
deleted or hidden. Account deletion removes the projection as part of cleanup;
until cleanup completes, candidate and delivery validation require a current
public profile and allowed account-safety state.

Message documents store server-resolved snapshots:

```text
mentions: [
  { userId: string, displayName: string }
]
```

The client sends only `mentionUserIds`. The callable verifies participant
records and resolves display names before writing the message.

## Search

- Empty query: most recently active participants.
- One normalized character: prefix matching.
- Two or more normalized characters: query one stored bigram, then verify the
  complete normalized substring on the server.
- Normalize with NFKC, lowercase Latin characters, collapsed whitespace, and
  Katakana-to-Hiragana folding.
- Return at most 20 results and never expose the participants collection to
  direct client reads.
- Exclude the sender, missing profiles, banned accounts, invalid private-note
  memberships, and either-direction block relationships.

## Delivery and deduplication

- Enqueue mention delivery only after a message is publicly visible and its
  moderation result is `allow`, `sensitive`, or `review`.
- Revalidate note/message state, recipient access, account safety, and blocks
  immediately before creating the recipient's notice.
- Use a deterministic source-world outbox event per message.
- Use the same deterministic ID for the recipient's home-world notice so
  retries cannot duplicate inbox entries or pushes.
- If a recipient is also a note creator or administrator, mention delivery
  takes precedence and the My Notes event excludes that recipient.
- Sensitive and review messages use the same generic copy and never expose a
  preview.

## Deferred

- Footprint-only participants
- `@all` or note-wide announcements
- Threaded replies and quoted reply snapshots
- Mention inbox filters and unread grouping
- Scheduled mentions
- Three-gram indexes unless production search metrics justify them

## Rollout

1. Deploy `firestore.indexes.json` and wait for the participant indexes to
   finish building in all three databases.
2. Deploy Functions, then the clients.
