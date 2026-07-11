# Note Likes

## Goal

Issue #23 adds likes for notes created by other users. The count must be
available in note summaries without extra per-note aggregation reads.

## Firestore Shape

```text
places/{placeId}
  likeCount: number

places/{placeId}/likes/{uid}
  userId: string
  placeId: string
  liked: boolean
  likedAt: timestamp | null
  updatedAt: timestamp
```

`places.likeCount` is the denormalized display counter. It is maintained only
by Cloud Functions and defaults to `0` for legacy documents.

`likes/{uid}` is the source of truth for the current user's state. The document
is kept after unliking with `liked: false` so repeated toggles do not create and
delete documents. Clients may read only their own like state and may not write
likes directly.

No `users/{uid}/likedNotes` mirror is added for the first version. If a liked
notes list becomes a product requirement, add a server-managed mirror then.

## Update Flow

Clients call `setNoteLike({placeId, liked})`. The callable function:

- requires authentication and App Check
- rejects likes on notes created by the caller
- allows likes only for readable, published, unexpired, non-archived notes
- verifies private-note membership unless the caller is a maintainer
- updates `likes/{uid}` and `places.likeCount` in one transaction
- treats repeated requests for the same final state as a no-op

The Flutter UI remains responsive while reducing server writes:

- each tap immediately flips the local heart and count
- only the final desired state is sent after a short trailing debounce
- if the user taps while a request is in flight, the final state is sent after
  the current request completes
- if a pending state returns to the server-confirmed state, no request is sent

No server-side in-memory token bucket is included. For this issue, client-side
debounce plus idempotent transaction behavior is enough.
