import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {getFirestore, FieldValue} from "firebase-admin/firestore";

import {REGION, MAX_MESSAGES_PER_THREAD} from "./constants";

/**
 * Maintains place.messageCount / lastMessageAt server-side.
 *
 * The counter used to be incremented by the client, but that required a
 * client-writable place field — which let any signed-in user tamper with any
 * note's count (block posting, reset the cap, reorder the list). Now the only
 * writer is this trigger; security rules deny client writes to those fields.
 *
 * It also performs the message-limit auto-close (Phase 3 #2's deferred piece):
 * when the count reaches the cap, the thread flips to closed so the writability
 * state reflects reality (rules already block the over-cap message itself).
 */
export const onMessageCreated = onDocumentCreated(
  {document: "places/{placeId}/messages/{messageId}", region: REGION},
  async (event) => {
    const db = getFirestore();
    const placeRef = db.collection("places").doc(event.params.placeId);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(placeRef);
      if (!snap.exists) return;

      const newCount = ((snap.get("messageCount") as number) ?? 0) + 1;
      const update: Record<string, unknown> = {
        messageCount: newCount,
        lastMessageAt: FieldValue.serverTimestamp(),
      };

      if (newCount >= MAX_MESSAGES_PER_THREAD && snap.get("isOpen") === true) {
        update.isOpen = false;
        update.closedReason = "messageLimit";
        update.closedAt = FieldValue.serverTimestamp();
      }

      tx.update(placeRef, update);
    });
  },
);
