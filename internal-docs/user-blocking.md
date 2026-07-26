# User blocking

## Relationship model

A block is a directed relationship stored at:

```text
users/{blockerUserId}/blockedUsers/{blockedUserId}
  createdAt: timestamp
```

Only the blocker can read this collection. Clients cannot write it directly;
`setUserBlock` is the authoritative mutation API.

Block and follow are separate concepts in storage, but a pair cannot remain
followed while either direction is blocked. Creating a block removes both
follow edges and adjusts both public profile counters. A later unblock does
not restore follows.

## Blocking effects

When user A blocks user B:

- Notes created by B are removed from A's map results and cannot be opened by
  direct link.
- Messages authored by B are filtered from A's message lists without a
  placeholder, hidden-message count, or block-specific empty state.
- Existing notification inbox items sourced from B, visitors from B, and B in
  follow/follower lists are filtered from A's client.
- Push notifications caused by B are not sent to A.
- Both follow directions are removed, and neither direction can be recreated
  while the block exists.
- B is removed from `maintainerIds` and `members/{B}` in every note owned by A,
  including archived notes.
- Unpublished scheduled messages authored by B in A-owned notes are deleted,
  their stored images are removed, and reserved message slots are released.
- B cannot regain access to A-owned notes through a password or invite and
  cannot post, visit, like, or perform maintainer actions there.

The server checks both block directions when enforcing interactions. This
prevents the blocked user from bypassing the UI and prevents races between
blocking and a concurrent follow, access, post, reaction, or maintenance
request.

## Third-party notes

If user C owns a note, a block between A and B does not change either user's
membership or maintainer permissions in C's note. Both can continue to
participate. A filters messages authored by B; B can still see messages
authored by A unless B also filters A by creating their own block.

This exception avoids silently changing a third party's access-control state.
Operational access lists may therefore still contain both users.

## Counts and empty state

`places.messageCount` and the 1,000-message capacity remain global note
properties. They include messages hidden from A because A blocked their
author. The existing new-message badge continues to use the global count and
keeps its existing wording.

The visible list is filtered before rendering. If it becomes empty, the normal
empty-state message remains unchanged; the UI does not explain that blocked
messages were removed.

Aggregate like and visitor counts also remain note-wide. Blocking does not
rewrite historical content, reports, moderation reviews, audit logs, or
aggregate counters.

## Unblocking

Unblocking only deletes the directed block document. Content may become
visible again, but follows, note membership, maintainer access, deleted
scheduled messages, and previous notification delivery are not restored.

## User interface

Block or unblock is available from:

- another user's profile;
- another author's message action sheet;
- a note creator's overflow menu;
- the report screen as an optional action after submitting a report;
- Settings > Blocked users.

Confirmation copy explains follow removal, access removal from owned notes,
the third-party-note exception, and the non-restoring behavior of unblock.
All block-specific copy is available in every supported locale.
