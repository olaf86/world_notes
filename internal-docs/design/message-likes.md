# Message Like state

## Decision

The app stores the current user's message Like state once per note:

```text
places/{placeId}/likedMessages/{uid}
  userId: uid
  placeId: placeId
  messageIds: string[]
  updatedAt: timestamp
```

The document is server-managed and readable only by its owner when that user
can access the parent note. The client cannot list the collection or write the
document directly.

This replaces the client-side pattern of opening one Like-state listener for
every displayed message. A thread now uses three long-lived reads regardless
of the number of displayed messages:

1. visible published messages;
2. the caller's scheduled messages;
3. the caller's exact note-scoped message Like-state document.

The older-message page query reuses one point read of the same Like-state
document. It does not subscribe to individual messages.

## Write consistency and bounds

`setMessageLike` runs in the note's Firestore database. One transaction reads
the parent note, target message, and the caller's liked-messages document, then
updates both `messageIds` and the message's aggregate `likeCount`.
Repeated requests for the same desired value are idempotent.

`messageIds` is sorted and unique. Its safety ceiling is 10,000 IDs and
500,000 UTF-8 bytes, below Firestore's document-size limit. This ceiling is
higher than the 1,000 visible-message limit because Likes for moderation-hidden
messages remain restorable for 30 days while replacement messages may be
published. The normal state is therefore much smaller than the safety ceiling.
Writes by the same user in the same note are serialized through one document;
this is acceptable for human Like interactions. The message aggregate remains
the possible contention point for a very popular message and can be sharded
later if production measurements require it.

The automatic array index for `messageIds` remains enabled. Normal client
reads do not query it, but the retention worker uses `array-contains` to remove
a permanently purged message ID from every affected state document.

## Retention

When a hidden message reaches its 30-day purge deadline, the cleanup worker:

1. removes the message ID from matching `likedMessages` documents in
   bounded batches;
2. deletes the message and its retained content after the cleanup barrier.

When a whole hidden note is purged, its `likedMessages` subcollection is
also drained before the parent note is deleted.

## Migration status

The first one-time production backfill completed on 2026-08-13 after a
compatible `setMessageLike` Function was deployed to all three regions. It
converted the old per-message Like documents into one aggregate document per
user and note. Results were:

- Asia: 13 old per-message documents scanned, 12 active Likes, and five
  aggregate state documents written;
- North America: no legacy edges;
- Europe: no legacy edges;
- a complete second pass reported `stateWrites=0` in every world.

A second one-time pass renamed the five Asia aggregate documents to the final
`likedMessages` collection and `messageIds` field; North America and Europe had
no aggregate documents to rename. A verification pass then reported zero old
documents in every world. The old documents were deleted and both migration
commands were removed after verification.

The `setMessageLike` Function, Security Rules, retention workers, tests, and
client now use only the final schema. Point-in-time recovery remains available
only for the configured Firestore recovery window.
