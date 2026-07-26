import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {getFirestore, FieldValue, Timestamp} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";

import {MAX_MESSAGES_PER_THREAD, REGION} from "./constants";
import {
  sendMyNotesMessageNotifications,
} from "./notifications";
import {hasUserBlockBetweenInTransaction} from "./userBlocks";

/**
 * Publishes scheduled messages whose publishAt has arrived.
 *
 * The hidden messageSlots counter already reserved capacity at send time. This
 * job increments the public messageCount when the message or moderation
 * tombstone becomes public.
 */
export const aggregatePublishedMessages = onSchedule(
  {schedule: "every 1 minutes", timeZone: "Asia/Tokyo", region: REGION},
  async () => {
    const db = getFirestore();
    const now = Timestamp.now();
    const batchSize = 100;

    const snap = await db
      .collectionGroup("messages")
      .where("placeAggregateAppliedAt", "==", null)
      .where("publishAt", "<=", now)
      .orderBy("publishAt")
      .limit(batchSize)
      .get();

    if (snap.empty) return;

    let applied = 0;
    const publishedMessages: Array<{
      placeId: string;
      messageId: string;
      senderId: string;
      notify: boolean;
    }> = [];
    await Promise.all(
      snap.docs.map(async (messageDoc) => {
        const placeRef = messageDoc.ref.parent.parent;
        if (!placeRef) return;
        const imagePathsToDelete = new Set<string>();

        await db.runTransaction(async (tx) => {
          const message = await tx.get(messageDoc.ref);
          if (!message.exists) return;
          if (message.get("placeAggregateAppliedAt") != null) return;
          const isModerationRemoval =
            message.get("deletedReason") === "moderation";
          if (
            (message.get("isDeleted") === true && !isModerationRemoval) ||
            message.get("isVisible") !== true
          ) {
            tx.update(messageDoc.ref, {
              placeAggregateAppliedAt: FieldValue.serverTimestamp(),
            });
            return;
          }

          const publishAt = message.get("publishAt") as Timestamp;
          if (publishAt.toMillis() > Date.now()) return;

          const place = await tx.get(placeRef);
          if (!place.exists) return;
          const senderId = message.get("userId") as string | undefined;
          const creatorUid =
            place.get("createdByUserId") as string | undefined;
          if (
            senderId &&
            creatorUid &&
            await hasUserBlockBetweenInTransaction(
              tx,
              db,
              senderId,
              creatorUid,
            )
          ) {
            const counterRef =
              placeRef.collection("counters").doc("messageSlots");
            const counter = await tx.get(counterRef);
            const publicCount =
              (place.get("messageCount") as number | undefined) ?? 0;
            const currentSlots = counter.exists ?
              ((counter.get("count") as number | undefined) ?? 0) :
              publicCount;
            const nextSlots = Math.max(0, currentSlots - 1);
            tx.set(
              counterRef,
              {
                count: nextSlots,
                updatedAt: FieldValue.serverTimestamp(),
              },
              {merge: true},
            );
            const expiresAt =
              place.get("expiresAt") as Timestamp | undefined;
            if (
              publicCount < MAX_MESSAGES_PER_THREAD &&
              nextSlots < MAX_MESSAGES_PER_THREAD &&
              place.get("closedReason") === "messageLimit" &&
              place.get("isArchived") !== true &&
              (!expiresAt || expiresAt.toMillis() > Date.now())
            ) {
              tx.update(placeRef, {
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
            tx.delete(messageDoc.ref);
            return;
          }

          const currentCount =
            (place.get("messageCount") as number | undefined) ?? 0;
          const newCount = currentCount + 1;
          const update: Record<string, unknown> = {
            messageCount: newCount,
          };
          const lastMessageAt =
            place.get("lastMessageAt") as Timestamp | undefined;
          if (
            !lastMessageAt ||
            lastMessageAt.toMillis() < publishAt.toMillis()
          ) {
            update.lastMessageAt = publishAt;
          }

          if (
            newCount >= MAX_MESSAGES_PER_THREAD &&
            place.get("isOpen") === true
          ) {
            update.isOpen = false;
            update.closedReason = "messageLimit";
            update.closedAt = FieldValue.serverTimestamp();
          }

          tx.update(placeRef, update);
          tx.update(messageDoc.ref, {
            placeAggregateAppliedAt: FieldValue.serverTimestamp(),
            isPubliclyVisible: true,
          });
          publishedMessages.push({
            placeId: placeRef.id,
            messageId: messageDoc.id,
            senderId: message.get("userId") as string,
            notify: !isModerationRemoval,
          });
          applied++;
        });
        if (imagePathsToDelete.size > 0) {
          const bucket = getStorage().bucket();
          await Promise.all([...imagePathsToDelete].map(async (path) => {
            try {
              await bucket.file(path).delete({ignoreNotFound: true});
            } catch (error) {
              logger.warn(
                `Could not delete blocked scheduled image ${path}.`,
                error,
              );
            }
          }));
        }
      }),
    );

    await Promise.all(
      publishedMessages.map(async ({placeId, messageId, senderId, notify}) => {
        if (!notify) return;
        try {
          await sendMyNotesMessageNotifications(
            db,
            placeId,
            messageId,
            senderId,
          );
        } catch (error) {
          logger.error(
            "aggregatePublishedMessages: failed to send My Notes " +
              `notification for places/${placeId}/messages/${messageId}.`,
            error,
          );
        }
      },
      ),
    );

    logger.info(
      `aggregatePublishedMessages: applied ${applied}/${snap.size} messages.`,
    );
  },
);
