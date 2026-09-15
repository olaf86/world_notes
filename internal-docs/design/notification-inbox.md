# Notification Inbox

## Status

Proposed product and implementation direction as of 2026-09-13.

## Purpose and Boundary

The notification inbox is a durable, account-scoped record of events that are
worth revisiting. It is not a chronological copy of every activity in the app.
An event belongs in the inbox when at least one of these is true:

- the recipient must make or may need to revisit a decision;
- the event directly addresses the recipient;
- the event changes account safety, access, or another durable entitlement;
- the operator needs to communicate important service information.

High-volume discovery signals remain outside the inbox:

- ordinary new messages stay in My Notes Push for creators and administrators,
  and in map activity indicators for other visitors;
- notes created by followed users remain map-discovery signals;
- Likes and footprints remain aggregate information on their existing screens;
- nearby-note alerts and background geofencing remain out of scope.

This preserves the separation already defined in
`notification-and-map-activity.md`: the inbox is durable and actionable, Push
is time-sensitive delivery, and the map is the discovery surface.

## Existing Behavior

The current app has one `NoticesScreen`. It is the inbox list, not a separate
list/detail pair.

When a row is tapped, the app marks it read without delaying the destination,
then applies one of these behaviors:

- a new-follower notice opens the follower's profile;
- a `mapNote` action switches content worlds and focuses the target note or
  message on the map;
- any notice without a recognized destination displays its title and complete
  body in a scrollable dialog.

The dialog is the initial detail presentation. Do not add a dedicated notice
detail route while notices contain only a title, plain-text body, and at most
one action. Reconsider a full detail screen if notices later gain rich content,
multiple actions, attachments, or a shareable URL.

The bottom navigation already displays a Material `Badge` over the notification
icon whenever `unreadNoticeCountProvider` is greater than zero. It displays the
unread count, caps the label at `99+`, and disappears as notices are marked
read. This badge means **unread inbox notices**; unseen messages inside note
threads continue to use their existing map and note activity indicators.

When at least one loaded notice is unread, the inbox AppBar displays a
`Mark all as read` action. It takes one snapshot of every unread notice in the
recipient's home-world inbox and updates that snapshot in Firestore batches of
at most 500 writes. A notice arriving after the snapshot remains unread. The
action is hidden when there is nothing to mark, disables itself while the write
is in progress, and reports a write failure without optimistically clearing the
unread state.

## Event Matrix

| Event | Inbox | Push | Tap behavior | Priority |
| --- | --- | --- | --- | --- |
| Welcome to World Notes | Yes | No | Informational dialog | P0 |
| New follower | Yes | Best effort | User profile | Existing |
| Mention | Yes | User preference | Map note/message target | Existing |
| Note-administrator invitation | Yes | Best effort | Invitation claim | P0 routing fix |
| Moderation warning/restriction/ban | Yes | Severity-dependent | Informational dialog; policy destination may be added later | Existing |
| Important operator/system announcement | Yes | Explicit per announcement | Dialog or allowlisted destination | As needed |
| Administrator invitation accepted | Candidate | No by default | Related note or informational dialog | P1 |
| Administrator access removed | Candidate | No by default | Informational dialog | P1 |
| Administrator resignation | Candidate for the note creator | No by default | Related note or informational dialog | P1 |
| User-report review completed | Candidate | No by default | Informational dialog | P1 |
| Subscription action required | Candidate | Only when time-sensitive | Subscription screen | Later |
| Note/message Like | No | No | Existing aggregate UI | Deferred |
| Footprint/visit | No | No | Existing visitor UI | Deferred |

Administrator lifecycle and report-result notices should be adopted only if
their production-safe delivery remains reasonably small. Both originate in a
content world but may target an account in another home world. They therefore
must not be added as an untracked best-effort write after the source
transaction. The source transaction should persist a deterministic routing
intent, and the existing home-world notice delivery path should consume it.

For report results, one moderation decision can resolve reports from multiple
reporters. Each reporter should receive at most one deterministic notice per
report document. Copy must say only that the review is complete and whether
the reported content was handled; it must not disclose private enforcement or
moderation details. If this fan-out and retry behavior requires a substantial
new subsystem, defer report-result notices.

For administrator changes, keep recipients narrow:

- an accepted invitation may notify the inviter;
- removal notifies the removed administrator;
- resignation may notify the note creator;
- revocation or expiry does not create a second notice initially because the
  invitation destination already presents its terminal state.

## Action Contract

Notice categories describe presentation and grouping; they must not determine
navigation. Navigation uses an explicit allowlisted semantic action. Initial
routes are:

- `userProfile` with `userId`;
- `mapNote` with `worldId`, `placeId`, coordinates, and optional `messageId`;
- `administratorInvitation` with `worldId` and signed invitation token;
- `subscription` with no arbitrary path;
- no action, which displays the informational dialog.

Unknown or invalid actions safely fall back to the informational dialog. Do not
execute an arbitrary route string from Firestore. The existing social-category
special case should migrate to `userProfile`, and the current administrator
invitation path must migrate to `administratorInvitation` so inbox taps reach
the claim screen.

## Welcome Notice

### Semantics

"First launch" means the first successful account bootstrap after the user
chooses an immutable home world. It does not mean the first launch of a device
installation. This gives one durable notice per account, keeps behavior
consistent across devices, and avoids duplicates after reinstalling.

Create the notice in the selected home-world Standard Edition database as part
of the authoritative account bootstrap. Use the deterministic document ID
`welcome`, create it unread, and do not send Push. Existing accounts are not
backfilled.

Suggested fields:

```text
users/{uid}/notices/welcome
  schemaVersion: 2
  category: "system"
  severity: "info"
  templateId: "welcome"
  templateVersion: 1
  content:
    locale: "ja"
    title: "セカイノートへようこそ"
    body: "..."
  action: null
  sourceType: "accountBootstrap"
  sourceId: null
  createdAt: timestamp
  readAt: null
```

Creating it in the same home-world transaction as the new account authority
bundle guarantees that a completed bootstrap cannot omit it. The deterministic
ID makes account-bootstrap retries idempotent. `content` is the canonical,
localized snapshot selected from `noticeTemplates/welcome`; it is not a
fallback. The per-user notice does not duplicate the template's other
languages.

`schemaVersion: 2` identifies the selected-language snapshot contract. Version
1 was the previous top-level `title`/`body` shape. Because there are no external
production users and the compatibility fallback was deliberately removed, the
client supports version 2 only and rejects legacy documents instead of guessing
their meaning. A future incompatible shape must increment this value and add an
explicit migration or compatibility path before rollout.

### Copy Direction

Japanese draft:

- Title: `セカイノートへようこそ`
- Body: `セカイノートでは、あなたの思い出や発見を、その場所に結びついたノートとして残せます。マップで近くのノートを見つけ、その場所を訪れた人たちとのメッセージも楽しんでみましょう。`

The copy presents creating a note and discovering nearby notes as equal primary
features. Every locale uses its existing localized product name while keeping
the surrounding sentence locale-native: `World Notes`, `セカイノート`,
`세계 일기`, `世界日记`, or `世界日記`. The body follows the same rule whenever it
names the app. Opening the notice displays this content in the existing dialog
and marks it read; no additional onboarding/detail screen is required
initially.

## Localization Policy

The central Firestore catalog is the runtime source for all inbox copy. Its
reviewed, version-controlled manifest is the authoring source used to deploy
that catalog; clients and notification workers do not read the repository
manifest. Use server-owned template masters containing every supported
localization:

```text
noticeTemplates/welcome
  templateId: "welcome"
  version: 1
  updatedAt: timestamp
  updatedBy: string
  localizedContent:
    en: { title: "Welcome to World Notes", body: "..." }
    ja: { title: "セカイノートへようこそ", body: "..." }
    ko: { title: "...", body: "..." }
    zh-Hans: { title: "...", body: "..." }
    zh-Hant: { title: "...", body: "..." }
```

The trusted notice producer loads the template, selects the recipient's
resolved locale, substitutes bounded dynamic values, and writes only that
completed localized snapshot to `users/{uid}/notices`. The Flutter inbox still
uses only its existing user-notice stream; clients never read
`noticeTemplates` and cannot write either templates or notice content.

The selected `content.locale`, `content.title`, and `content.body` are the
canonical record of what the user received. Do not store compatibility fallback
fields. Changing the app language affects newly created notices but does not
rewrite historical notices. This immutability keeps the inbox and the Push copy
consistent and avoids a bulk rewrite on every language change.

Dynamic notices use the same templates. For example, a follower template
contains a bounded display-name placeholder. The server resolves the selected
localized copy before persisting it; arbitrary client-supplied template values
are never accepted.

Push delivery reads the finalized title and body from the per-user notice, so
it does not need a template lookup and cannot diverge from the inbox. The
account stores a last-resolved locale for notice creation, including when the
language preference is `system`. An explicit language selection updates it;
device registration refreshes it for a system-language selection.

Account bootstrap receives both `languagePreference` and `resolvedLocale`.
The former preserves whether the user follows the system or chose a language
explicitly; the latter is the concrete locale required to create the immutable
welcome snapshot. They coincide for an explicit language but represent
different facts for the `system` preference, so both remain required in the
callable contract.

An immediate operator announcement uses its own template document. Before
dispatch, an authorized operator may replace its complete multilingual content
and increment `version`. The dispatch job captures one validated template
version and its content before fan-out, so an edit during delivery cannot split
one announcement across two versions. Correcting an already dispatched
announcement requires a new correction notice; updating the template alone
does not mutate historical per-user copies.

Template masters have one authority: the Asia `(default)` database, which
already owns the global directory and coordination data. They are not
replicated to every home world. A trusted producer reads the current template
and version from this central catalog before creating a notice. Producers
outside Asia may therefore make one small server-side cross-region
configuration read at notice-creation time. This does not add a client read
path or a Push-delivery dependency. A transient catalog failure leaves the
deterministic notification intent retryable; it must not roll back the source
domain mutation. If reads later need caching, use a short bounded TTL so
operator updates become visible predictably.

Templates are maintained by authorized operations administrators; initially a
developer performs that role through a version-controlled source manifest and
a reviewed deployment command. The command validates the complete replacement
document's schema, required locales, length limits, and placeholder sets, then
atomically overwrites the stable document while incrementing `version`. It uses
a version precondition so concurrent updates cannot be lost. Rollback writes
the previous content as another higher version rather than decreasing the
counter. Direct Firebase Console edits are not part of the normal workflow.
Because there are no regional replicas, templates do not have a synchronization
or activation status.

If a dedicated operations interface is added later, it must use the same
validated compare-and-set update path. A separate draft/publish status may be
useful for scheduled announcements, but it describes editorial publication,
not cross-world synchronization.

Each selected title remains limited to 120 characters and each body to 2,000
characters. The large multilingual master is stored only once centrally and
each user receives one language, substantially reducing per-user storage and
inbox network transfer compared with embedding every language in every notice.
Neither template content nor finalized notice content is queried, so these
fields should be exempted from Firestore indexing.

### Adding a Language

Adding a language does not require rewriting historical per-user notices,
because they retain the language in which they were originally created:

1. add the locale to every source-manifest template and validate it;
2. atomically replace each central template and increment its version;
3. update resolved-locale registration and Push tests;
4. enable the Flutter locale only after the central catalog is verified.

New notices use the new locale. Existing notices remain valid immutable
snapshots, so there is no missing-locale fallback or historical backfill.

### Current-schema Migration

There are no external production users, so migrate all existing notification
producers now instead of maintaining a compatibility period:

1. create and validate versioned template masters for follower, mention,
   administrator invitation, moderation, ban, developer/system, and welcome
   notices;
2. deploy the validated template catalog once to the Asia `(default)` database;
3. change `CreateUserNoticeInput` to accept a trusted `templateId`, bounded
   substitution values, and the recipient's resolved locale;
4. store the finalized `content` snapshot plus `templateId` and
   `templateVersion` in the per-user notice and use that same snapshot for Push;
5. expand locale handling from the current English/Japanese subset to every
   app locale and persist the account's last-resolved locale;
6. update the Flutter entity/model and strict Firestore validator for the
   version-2 fields;
7. migrate retained development notices to `schemaVersion: 2`, then verify no
   legacy notification documents remain before removing legacy parsing;
8. exempt master and finalized content fields from single-field indexing.

## Initial Delivery Plan

1. Introduce and test the allowlisted semantic action parser.
2. Migrate follower and administrator-invitation navigation to explicit
   actions, fixing the current invitation inbox route.
3. Create the versioned Firestore template masters and migrate every existing
   producer and consumer to the version-2 selected-language snapshot schema.
4. Create the deterministic `welcome` notice atomically during new-account
   bootstrap.
5. Verify unread badge behavior from one unread welcome notice through opening
   and marking it read.
6. Evaluate administrator lifecycle delivery as the first P1 addition.
7. Add report-result notices only after confirming bounded, durable
   cross-world fan-out can reuse the same routing infrastructure.

## Verification

- Function unit tests prove deterministic welcome creation and bootstrap retry
  idempotency.
- Firestore emulator tests prove clients cannot create or alter notice content
  and may change only `readAt`.
- Widget tests prove the finalized selected-language content is displayed, the
  welcome row opens the dialog, and the unread badge clears after the server
  stream updates.
- Navigation tests cover every allowlisted action and invalid-action fallback.
- Administrator invitation tests cover list taps and notification-launch taps.
- Multi-world tests prove notices are read from and written to the recipient's
  home world.
