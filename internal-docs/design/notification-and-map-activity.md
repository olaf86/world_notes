# Notification and Map Activity

## Product Rules

World Notes separates social relationships, actionable push notifications,
and map discovery:

- `socialEdges` stores only user-to-user following. It does not contain push
  preferences.
- My Notes push notifications remain limited to creators and maintainers,
  because they can open and act on a note remotely.
- Regular visitors and participants discover updates through map markers and
  the map notes list. Merely visiting a note never enables native push.
- A newly followed user is added to the existing notice inbox. Push delivery
  is best effort when the recipient has already granted notification
  permission and registered a token.
- Nearby Note Alerts and all background geofencing are removed.

## Viewer State

The server stores only private, minimal per-user state. Location and display
metadata are not copied into this document.

```text
users/{uid}/noteStates/{placeId}
  lastSeenMessageCount: number
  lastOpenedAt: timestamp
  discoverySeenAt: timestamp
  participatedAt: timestamp?
  updatedAt: timestamp
```

`places.messageCount` is a published-message sequence for this purpose. The
current product soft-deletes published messages without decrementing the
count, while canceling an unpublished scheduled message never increments it.
Therefore:

```text
hasUnseenMessages = place.messageCount > noteState.lastSeenMessageCount
```

If a future product change makes edits, deletions, or restorations count as a
new activity, introduce a separate monotonic activity version at that time.

`recordNoteVisit` updates `noteStates` for every successfully opened note,
even when public visitor footprints are disabled. Sending a message records
`participatedAt`; an immediately published message also advances the sender's
seen count.

All `noteStates` writes are server-managed. Clients do not read them directly.

## One-Pass Map Composition

`listMapPins` remains the only map-loading request. After the bounded place
queries return at most 120 pins (60 while zoomed out), the function performs
two groups of parallel, chunked queries:

1. the caller's `noteStates` for the returned place ids;
2. the caller's `socialEdges` for the returned creator ids.

It then returns independent marker flags. An empty array is the normal state:

```text
[]
[followedAuthorNew]
[unseenMessages]
[followedAuthorNew, unseenMessages]
```

A followed-author note is considered new when it is public, was published in
the last seven days, and the caller has not subsequently opened it. The
client receives no intermediate join state and performs no per-pin reads.

Map markers use a stable-size visual treatment:

- an outer discovery ring and soft static halo for a recent note by a followed
  user;
- a prominent alert badge for a previously opened or participated note with a larger
  `messageCount` than the caller last saw;
- both treatments when both states apply.

The map notes list and marker bottom sheet reuse the same server-computed state
as filled status badges. The unseen-message badge gives two soft pulses when it
enters the viewport, then stops; reduced-motion settings disable the pulse. No
filter or mode switch is added to the map.

## Cost Shape

Map composition is bounded by the existing pin limit. Additional reads are
limited to matching viewer-state and follow-edge documents plus Firestore's
minimum charge for each chunked query. Message publication does not fan out
writes to visitors or followers; it continues to update the existing place
aggregate once. Each real note open adds one private viewer-state write.

This design favors bounded reads during an explicit map refresh over
unbounded per-message fan-out writes, while keeping the read model rebuildable
from `places`, `socialEdges`, and user interactions.
