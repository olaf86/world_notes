/* eslint-disable require-jsdoc, valid-jsdoc */

import {
  FieldPath,
  FieldValue,
  Timestamp,
} from "firebase-admin/firestore";

import {MAX_MESSAGES_PER_THREAD} from "./constants";
import {
  CleanupBatchContext,
  CleanupBatchResult,
  CleanupJobHandler,
} from "./cleanupJobs";
import {derivedGlobalOperationId} from "./globalOperations";
import {executeSocialEdgeCommand} from "./socialEdgeReplication";
import {enqueueStorageObjectDeletion} from "./storageObjectCleanup";
import {
  BLOCK_RELATIONSHIP_CLEANUP_JOB,
  parseUserBlockEntityId,
  parseUserBlockProjection,
  userBlockRef,
} from "./userBlockReplication";

const SCHEDULED_MESSAGE_BATCH_SIZE = 50;
const OWNED_PLACES_CLEANUP_STAGE = "ownedPlaces" as const;

interface BlockCleanupCursor {
  readonly stage: typeof OWNED_PLACES_CLEANUP_STAGE;
  readonly ownerIndex: 0 | 1;
  readonly afterPlaceId: string | null;
  readonly currentPlaceId: string | null;
  readonly pass: number;
}

/** Removes permanent relationship state after local enforcement is durable. */
export const blockRelationshipCleanupHandler: CleanupJobHandler = {
  queue: "firestore",
  jobType: BLOCK_RELATIONSHIP_CLEANUP_JOB,
  processBatch: processBlockCleanupBatch,
};

async function processBlockCleanupBatch(
  context: CleanupBatchContext,
): Promise<CleanupBatchResult> {
  // Cleanup is intentionally ordered: apply enforcement, remove both follow
  // directions through their authorities, then page through each user's notes.
  const pair = parseUserBlockEntityId(context.job.entityId);
  await assertBlockRevisionApplied(context, pair);
  if (context.job.cursor === null) {
    await removeFollowAuthorities(context, pair);
    return {
      complete: false,
      cursor: encodeCursor({
        stage: OWNED_PLACES_CLEANUP_STAGE,
        ownerIndex: 0,
        afterPlaceId: null,
        currentPlaceId: null,
        pass: 0,
      }),
    };
  }

  const cursor = parseCursor(context.job.cursor);
  const owners = [pair.blockerUid, pair.blockedUid] as const;
  const peers = [pair.blockedUid, pair.blockerUid] as const;
  const ownerUid = owners[cursor.ownerIndex];
  const peerUid = peers[cursor.ownerIndex];
  const placeId = cursor.currentPlaceId ??
    await nextOwnedPlaceId(context, ownerUid, cursor.afterPlaceId);
  if (placeId === null) {
    if (cursor.ownerIndex === 1) return {complete: true};
    return {
      complete: false,
      cursor: encodeCursor({
        stage: OWNED_PLACES_CLEANUP_STAGE,
        ownerIndex: 1,
        afterPlaceId: null,
        currentPlaceId: null,
        pass: 0,
      }),
    };
  }

  const hasMoreMessages = await cleanOwnedPlace(
    context,
    ownerUid,
    peerUid,
    placeId,
  );
  return {
    complete: false,
    cursor: encodeCursor({
      stage: OWNED_PLACES_CLEANUP_STAGE,
      ownerIndex: cursor.ownerIndex,
      afterPlaceId: hasMoreMessages ? cursor.afterPlaceId : placeId,
      currentPlaceId: hasMoreMessages ? placeId : null,
      pass: cursor.pass + 1,
    }),
  };
}

async function assertBlockRevisionApplied(
  context: CleanupBatchContext,
  pair: Readonly<{blockerUid: string; blockedUid: string}>,
): Promise<void> {
  // Destructive cleanup may start only after this world's block projection is
  // at least as new as the operation that created the cleanup intent.
  const snapshot = await userBlockRef(
    context.firestore,
    pair.blockerUid,
    pair.blockedUid,
  ).get();
  const block = parseUserBlockProjection(
    snapshot,
    pair.blockerUid,
    pair.blockedUid,
  );
  if (block.revision < context.job.revision) {
    throw new Error("Block cleanup started before its revision was applied.");
  }
}

async function removeFollowAuthorities(
  context: CleanupBatchContext,
  pair: Readonly<{blockerUid: string; blockedUid: string}>,
): Promise<void> {
  // A follow edge belongs to its follower's home world. Each world's cleanup
  // worker therefore removes only the directions for which it is authoritative.
  const [blockerHome, blockedHome] = await Promise.all([
    context.firestore.collection("userHomes").doc(pair.blockerUid).get(),
    context.firestore.collection("userHomes").doc(pair.blockedUid).get(),
  ]);
  const directions = [
    {
      followerUid: pair.blockerUid,
      followeeUid: pair.blockedUid,
      home: blockerHome,
    },
    {
      followerUid: pair.blockedUid,
      followeeUid: pair.blockerUid,
      home: blockedHome,
    },
  ] as const;
  for (const direction of directions) {
    if (direction.home.get("world") !== context.job.world) continue;
    await executeSocialEdgeCommand({
      firestore: context.firestore,
      authorityWorld: context.job.world,
      followerUid: direction.followerUid,
      followeeUid: direction.followeeUid,
      following: false,
      operationId: derivedGlobalOperationId(
        context.job.sourceOperationId,
        `block-follow:${direction.followerUid}:${direction.followeeUid}`,
      ),
      sourceEventId: `blockCleanup:${context.job.sourceOperationId}`,
    });
  }
}

async function nextOwnedPlaceId(
  context: CleanupBatchContext,
  ownerUid: string,
  afterPlaceId: string | null,
): Promise<string | null> {
  let query = context.firestore
    .collection("places")
    .where("createdByUserId", "==", ownerUid)
    .orderBy(FieldPath.documentId())
    .limit(1);
  if (afterPlaceId !== null) query = query.startAfter(afterPlaceId);
  const snapshot = await query.get();
  return snapshot.empty ? null : snapshot.docs[0].id;
}

async function cleanOwnedPlace(
  context: CleanupBatchContext,
  ownerUid: string,
  peerUid: string,
  placeId: string,
): Promise<boolean> {
  return context.firestore.runTransaction(async (transaction) => {
    const placeRef = context.firestore.collection("places").doc(placeId);
    const counterRef = placeRef.collection("counters").doc("messageSlots");
    const memberRef = placeRef.collection("members").doc(peerUid);
    const messagesQuery = placeRef
      .collection("messages")
      .where("userId", "==", peerUid)
      .where("isPubliclyVisible", "==", false)
      .where("placeAggregateAppliedAt", "==", null)
      .limit(SCHEDULED_MESSAGE_BATCH_SIZE);
    const [place, counter, messages] = await Promise.all([
      transaction.get(placeRef),
      transaction.get(counterRef),
      transaction.get(messagesQuery),
    ]);
    if (!place.exists) return false;
    if (place.get("createdByUserId") !== ownerUid) {
      throw new Error("Block cleanup note ownership changed.");
    }

    const objectPaths = new Set<string>();
    for (const message of messages.docs) {
      const paths = message.get("imageStoragePaths");
      if (Array.isArray(paths)) {
        for (const path of paths) {
          if (typeof path === "string" && path.length > 0) {
            objectPaths.add(path);
          }
        }
      }
    }
    const createdAt = Timestamp.now();
    for (const objectPath of objectPaths) {
      enqueueStorageObjectDeletion(
        transaction,
        context.firestore,
        {
          sourceOperationId: context.job.sourceOperationId,
          revision: context.job.revision,
          world: context.job.world,
          objectPath,
          createdAt,
        },
      );
    }

    transaction.update(placeRef, {
      maintainerIds: FieldValue.arrayRemove(peerUid),
    });
    transaction.delete(memberRef);
    for (const message of messages.docs) transaction.delete(message.ref);

    if (!messages.empty) {
      const publicCount = nonNegativeCount(place.get("messageCount"));
      const currentSlots = counter.exists ?
        nonNegativeCount(counter.get("count")) :
        publicCount;
      const nextSlots = Math.max(0, currentSlots - messages.size);
      transaction.set(counterRef, {
        count: nextSlots,
        updatedAt: createdAt,
      }, {merge: true});
      const expiresAt = place.get("expiresAt");
      if (publicCount < MAX_MESSAGES_PER_THREAD &&
          nextSlots < MAX_MESSAGES_PER_THREAD &&
          place.get("closedReason") === "messageLimit" &&
          place.get("isArchived") !== true &&
          (!(expiresAt instanceof Timestamp) ||
           expiresAt.toMillis() > createdAt.toMillis())) {
        transaction.update(placeRef, {
          isOpen: true,
          closedReason: FieldValue.delete(),
          closedAt: FieldValue.delete(),
        });
      }
    }
    return messages.size === SCHEDULED_MESSAGE_BATCH_SIZE;
  });
}

function nonNegativeCount(value: unknown): number {
  if (typeof value !== "number" ||
      !Number.isSafeInteger(value) || value < 0) {
    throw new Error("Block cleanup counter is invalid.");
  }
  return value;
}

function encodeCursor(cursor: BlockCleanupCursor): string {
  return JSON.stringify(cursor);
}

function parseCursor(value: string): BlockCleanupCursor {
  const parsed = JSON.parse(value) as unknown;
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error("Block cleanup cursor is invalid.");
  }
  const cursor = parsed as Record<string, unknown>;
  if (cursor.stage !== OWNED_PLACES_CLEANUP_STAGE ||
      (cursor.ownerIndex !== 0 && cursor.ownerIndex !== 1) ||
      !nullableString(cursor.afterPlaceId) ||
      !nullableString(cursor.currentPlaceId) ||
      typeof cursor.pass !== "number" ||
      !Number.isSafeInteger(cursor.pass) || cursor.pass < 0) {
    throw new Error("Block cleanup cursor is invalid.");
  }
  return cursor as unknown as BlockCleanupCursor;
}

function nullableString(value: unknown): boolean {
  return value === null ||
    (typeof value === "string" && value.length > 0 && value.length <= 256);
}
