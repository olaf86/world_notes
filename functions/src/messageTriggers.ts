import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {getFirestore, FieldValue, Timestamp} from "firebase-admin/firestore";

import {MAX_MESSAGES_PER_THREAD, REGION} from "./constants";
import {
  sendMyNotesMessageNotifications,
  sendNearbyInRangeMessageNotifications,
} from "./notifications";

/**
 * Publishes scheduled messages whose publishAt has arrived.
 *
 * The hidden messageSlots counter already reserved capacity at send time. This
 * job increments the public messageCount only when the message becomes public.
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
    }> = [];
    await Promise.all(
      snap.docs.map(async (messageDoc) => {
        const placeRef = messageDoc.ref.parent.parent;
        if (!placeRef) return;

        await db.runTransaction(async (tx) => {
          const message = await tx.get(messageDoc.ref);
          if (!message.exists) return;
          if (message.get("placeAggregateAppliedAt") != null) return;
          if (
            message.get("isDeleted") === true ||
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
          });
          applied++;
        });
      }),
    );

    await Promise.all(
      publishedMessages.map(async ({placeId, messageId, senderId}) => {
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
        try {
          await sendNearbyInRangeMessageNotifications(
            db,
            placeId,
            messageId,
            senderId,
          );
        } catch (error) {
          logger.error(
            "aggregatePublishedMessages: failed to send nearby " +
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
