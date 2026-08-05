import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {FieldPath, FieldValue, Timestamp} from "firebase-admin/firestore";

import {MAX_MESSAGES_PER_THREAD} from "./constants";
import {worldContext} from "./platform/worldContext";
import {WORLD_REGISTRY} from "./platform/worldRegistry";
import {
  enqueueMyNotesMessageNotification,
} from "./notifications";
import {hasUserBlockBetweenInTransaction} from "./userBlocks";

const SCHEDULED_MESSAGE_BATCH_SIZE = 100;
const SCHEDULED_MESSAGE_MAX_BATCHES = 10;

export interface ScheduledMessagePublicationResult {
  readonly inspected: number;
  readonly processed: number;
  readonly published: number;
}

/**
 * Publishes a bounded backlog of due messages in one world.
 *
 * The hidden messageSlots counter already reserved capacity at send time. This
 * worker increments the public messageCount only after moderation has reached
 * a visible terminal state. Hidden tombstones are marked processed without
 * becoming public. Cursor pagination lets one invocation inspect up to 1,000
 * due documents without repeatedly selecting the first fixed page.
 *
 * @param {string} worldId Trusted catalog world to process.
 * @return {Promise<ScheduledMessagePublicationResult>} Processing totals.
 */
export async function publishScheduledMessagesForWorld(
  worldId: string,
): Promise<ScheduledMessagePublicationResult> {
  const world = worldContext(worldId);
  const db = world.firestore;
  const now = Timestamp.now();
  let inspected = 0;
  let processed = 0;
  let published = 0;
  let after:
    FirebaseFirestore.QueryDocumentSnapshot | undefined;

  for (
    let batchIndex = 0;
    batchIndex < SCHEDULED_MESSAGE_MAX_BATCHES;
    batchIndex += 1
  ) {
    let query = db
      .collectionGroup("messages")
      .where("placeAggregateAppliedAt", "==", null)
      .where(
        "moderationAction",
        "in",
        ["allow", "sensitive", "review", "hidden"],
      )
      .where("publishAt", "<=", now)
      .orderBy("publishAt")
      .orderBy(FieldPath.documentId())
      .limit(SCHEDULED_MESSAGE_BATCH_SIZE);
    if (after !== undefined) query = query.startAfter(after);
    const snapshot = await query.get();
    if (snapshot.empty) break;
    inspected += snapshot.size;
    after = snapshot.docs[snapshot.docs.length - 1];

    const batchResults = await Promise.all(
      snapshot.docs.map(async (messageDocument) => {
        const placeRef = messageDocument.ref.parent.parent;
        if (placeRef === null) return {processed: false, published: false};
        const imagePathsToDelete = new Set<string>();

        const result = await db.runTransaction(async (transaction) => {
          const message = await transaction.get(messageDocument.ref);
          if (!message.exists ||
              message.get("placeAggregateAppliedAt") != null) {
            return {processed: false, published: false};
          }
          const isModerationRemoval =
            message.get("deletedReason") === "moderation";
          if ((message.get("isDeleted") === true && !isModerationRemoval) ||
              message.get("isVisible") !== true) {
            transaction.update(messageDocument.ref, {
              placeAggregateAppliedAt: FieldValue.serverTimestamp(),
            });
            return {processed: true, published: false};
          }

          const publishAt = message.get("publishAt") as Timestamp;
          if (publishAt.toMillis() > now.toMillis()) {
            return {processed: false, published: false};
          }

          const place = await transaction.get(placeRef);
          if (!place.exists) return {processed: false, published: false};
          const senderId = message.get("userId") as string | undefined;
          const creatorUid =
            place.get("createdByUserId") as string | undefined;
          if (senderId && creatorUid &&
              await hasUserBlockBetweenInTransaction(
                transaction,
                db,
                senderId,
                creatorUid,
              )) {
            const counterRef =
              placeRef.collection("counters").doc("messageSlots");
            const counter = await transaction.get(counterRef);
            const publicCount =
              (place.get("messageCount") as number | undefined) ?? 0;
            const currentSlots = counter.exists ?
              ((counter.get("count") as number | undefined) ?? 0) :
              publicCount;
            const nextSlots = Math.max(0, currentSlots - 1);
            transaction.set(
              counterRef,
              {
                count: nextSlots,
                updatedAt: FieldValue.serverTimestamp(),
              },
              {merge: true},
            );
            const expiresAt = place.get("expiresAt") as Timestamp | undefined;
            if (publicCount < MAX_MESSAGES_PER_THREAD &&
                nextSlots < MAX_MESSAGES_PER_THREAD &&
                place.get("closedReason") === "messageLimit" &&
                place.get("isArchived") !== true &&
                (!expiresAt || expiresAt.toMillis() > now.toMillis())) {
              transaction.update(placeRef, {
                isOpen: true,
                closedReason: FieldValue.delete(),
                closedAt: FieldValue.delete(),
              });
            }
            const storedPaths = message.get("imageStoragePaths");
            if (Array.isArray(storedPaths)) {
              for (const path of storedPaths) {
                if (typeof path === "string" && path.length > 0) {
                  imagePathsToDelete.add(path);
                }
              }
            }
            transaction.delete(messageDocument.ref);
            return {processed: true, published: false};
          }

          const currentCount =
            (place.get("messageCount") as number | undefined) ?? 0;
          const newCount = currentCount + 1;
          const update: Record<string, unknown> = {messageCount: newCount};
          const lastMessageAt =
            place.get("lastMessageAt") as Timestamp | undefined;
          if (!lastMessageAt ||
              lastMessageAt.toMillis() < publishAt.toMillis()) {
            update.lastMessageAt = publishAt;
          }
          if (newCount >= MAX_MESSAGES_PER_THREAD &&
              place.get("isOpen") === true) {
            update.isOpen = false;
            update.closedReason = "messageLimit";
            update.closedAt = FieldValue.serverTimestamp();
          }

          transaction.update(placeRef, update);
          transaction.update(messageDocument.ref, {
            placeAggregateAppliedAt: FieldValue.serverTimestamp(),
            isPubliclyVisible: true,
          });
          if (!isModerationRemoval && typeof senderId === "string") {
            enqueueMyNotesMessageNotification(transaction, db, {
              sourceWorld: worldId,
              place,
              messageId: messageDocument.id,
              senderId,
              createdAt: now,
            });
          }
          return {processed: true, published: true};
        });

        if (imagePathsToDelete.size > 0) {
          await Promise.all([...imagePathsToDelete].map(async (path) => {
            try {
              await world.bucket.file(path).delete({ignoreNotFound: true});
            } catch (error) {
              logger.warn(
                `Could not delete blocked scheduled image ${path}.`,
                error,
              );
            }
          }));
        }
        return result;
      }),
    );
    processed += batchResults.filter((result) => result.processed).length;
    published += batchResults.filter((result) => result.published).length;
    if (snapshot.size < SCHEDULED_MESSAGE_BATCH_SIZE) break;
  }

  logger.info("Scheduled-message publication finished.", {
    worldId,
    inspected,
    processed,
    published,
  });
  return {inspected, processed, published};
}

/**
 * Creates one regional scheduled-message publisher.
 *
 * @param {string} worldId Trusted catalog world to process.
 * @return {ScheduleFunction} Regional scheduled function.
 */
function scheduledMessagePublicationSchedule(worldId: string) {
  const world = WORLD_REGISTRY.requireWorld(worldId);
  return onSchedule(
    {
      schedule: "every 1 minutes",
      timeZone: "Etc/UTC",
      region: world.functionsRegion,
      retryCount: 3,
      maxInstances: 1,
    },
    async () => {
      await publishScheduledMessagesForWorld(worldId);
    },
  );
}

export const publishAsiaScheduledMessages =
  scheduledMessagePublicationSchedule("asia");
export const publishNorthAmericaScheduledMessages =
  scheduledMessagePublicationSchedule("northAmerica");
export const publishEuropeScheduledMessages =
  scheduledMessagePublicationSchedule("europe");
