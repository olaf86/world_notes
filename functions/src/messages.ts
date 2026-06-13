/* eslint-disable require-jsdoc */
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {
  DocumentSnapshot,
  FieldValue,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

import {
  MAX_MESSAGE_PUBLISH_DELAY_DAYS,
  MAX_MESSAGES_PER_THREAD,
  REGION,
} from "./constants";
import {profileForMember} from "./userProfile";
import {
  sendMyNotesMessageNotifications,
  sendNearbyInRangeMessageNotifications,
} from "./notifications";

interface SendMessageData {
  placeId?: unknown;
  content?: unknown;
  imageUrl?: unknown;
  publishAtMillis?: unknown;
}

interface CancelScheduledMessageData {
  placeId?: unknown;
  messageId?: unknown;
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ?
    value.trim() :
    null;
}

function photoUrlFor(tokenPicture: unknown): string | null {
  return stringOrNull(tokenPicture);
}

function ownerIdsOf(placeSnap: DocumentSnapshot): string[] {
  const ownerIds = placeSnap.get("ownerIds") as string[] | undefined;
  return ownerIds ?? [];
}

function isOwner(placeSnap: DocumentSnapshot, uid: string): boolean {
  return placeSnap.get("createdByUserId") === uid ||
    ownerIdsOf(placeSnap).includes(uid);
}

function hasValidMembership(
  placeSnap: DocumentSnapshot,
  memberSnap: DocumentSnapshot | null,
): boolean {
  if (!memberSnap?.exists) return false;
  return memberSnap.get("invited") === true ||
    memberSnap.get("viaPasswordVersion") === placeSnap.get("passwordVersion");
}

function canAccessNote(
  placeSnap: DocumentSnapshot,
  memberSnap: DocumentSnapshot | null,
  uid: string,
): boolean {
  if (placeSnap.get("visibility") !== "private") return true;
  if (isOwner(placeSnap, uid)) return true;
  return hasValidMembership(placeSnap, memberSnap);
}

function messageSlotCount(
  counterSnap: DocumentSnapshot,
  initialPublicCount: number,
): number {
  return counterSnap.exists ?
    ((counterSnap.get("count") as number | undefined) ?? 0) :
    initialPublicCount;
}

function validatePlaceCanAccept(placeSnap: DocumentSnapshot, nowMs: number) {
  if (placeSnap.get("isOpen") !== true) {
    throw new HttpsError("failed-precondition", "This note is closed.");
  }
  if (placeSnap.get("isArchived") === true) {
    throw new HttpsError("failed-precondition", "This note is archived.");
  }
  const placePublishAt = placeSnap.get("publishAt") as Timestamp | undefined;
  if (placePublishAt && placePublishAt.toMillis() > nowMs) {
    throw new HttpsError(
      "failed-precondition",
      "This note is not published yet.",
    );
  }
  const expiresAt = placeSnap.get("expiresAt") as Timestamp | undefined;
  if (!expiresAt || expiresAt.toMillis() <= nowMs) {
    throw new HttpsError("failed-precondition", "This note has expired.");
  }
}

function validatePublishAt(
  rawPublishAtMillis: unknown,
  nowMs: number,
  placeSnap: DocumentSnapshot,
): Timestamp {
  let publishAtMs = nowMs;
  if (rawPublishAtMillis != null) {
    if (
      typeof rawPublishAtMillis !== "number" ||
      !isFinite(rawPublishAtMillis)
    ) {
      throw new HttpsError("invalid-argument", "Invalid publication time.");
    }
    const maxPublishAtMs =
      nowMs + MAX_MESSAGE_PUBLISH_DELAY_DAYS * 24 * 60 * 60 * 1000;
    if (rawPublishAtMillis > maxPublishAtMs) {
      throw new HttpsError(
        "invalid-argument",
        "Publication time is too far in the future.",
      );
    }
    publishAtMs = Math.max(rawPublishAtMillis, nowMs);
  }

  const expiresAt = placeSnap.get("expiresAt") as Timestamp | undefined;
  if (!expiresAt || publishAtMs >= expiresAt.toMillis()) {
    throw new HttpsError(
      "failed-precondition",
      "Publication time must be before the note expires.",
    );
  }
  return Timestamp.fromMillis(publishAtMs);
}

/**
 * Authoritative message creation.
 *
 * places.messageCount is public and counts only publicly visible messages.
 * places/{placeId}/counters/messageSlots.count is server-only and includes
 * scheduled messages immediately for cap enforcement.
 */
export const sendMessage = onCall<SendMessageData>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const {placeId, content, imageUrl, publishAtMillis} = req.data ?? {};
    if (typeof placeId !== "string" || placeId.length === 0) {
      throw new HttpsError("invalid-argument", "placeId is required.");
    }
    const trimmedContent =
      typeof content === "string" ? content.trim() : "";
    if (trimmedContent.length > 2000) {
      throw new HttpsError("invalid-argument", "Message is too long.");
    }
    const trimmedImageUrl = imageUrl == null ? null : stringOrNull(imageUrl);
    if (
      imageUrl != null &&
      (!trimmedImageUrl || trimmedImageUrl.length > 2000)
    ) {
      throw new HttpsError("invalid-argument", "Invalid image URL.");
    }
    if (trimmedContent.length === 0 && !trimmedImageUrl) {
      throw new HttpsError(
        "invalid-argument",
        "Message content or image is required.",
      );
    }

    const db = getFirestore();
    const placeRef = db.collection("places").doc(placeId);
    const memberRef = placeRef.collection("members").doc(uid);
    const counterRef = placeRef.collection("counters").doc("messageSlots");
    const messageRef = placeRef.collection("messages").doc();
    const nowMs = Date.now();
    const profile = await profileForMember(
      uid,
      req.auth?.token.name,
      req.auth?.token.email,
    );
    let publishedImmediately = false;

    await db.runTransaction(async (tx) => {
      const placeSnap = await tx.get(placeRef);
      if (!placeSnap.exists) {
        throw new HttpsError("not-found", "Note not found.");
      }
      const memberSnap =
        placeSnap.get("visibility") === "private" && !isOwner(placeSnap, uid) ?
          await tx.get(memberRef) :
          null;
      if (!canAccessNote(placeSnap, memberSnap, uid)) {
        throw new HttpsError(
          "permission-denied",
          "You cannot access this note.",
        );
      }
      const counterSnap = await tx.get(counterRef);

      validatePlaceCanAccept(placeSnap, nowMs);
      const publicCount =
        (placeSnap.get("messageCount") as number | undefined) ?? 0;
      const currentSlots =
        messageSlotCount(counterSnap, publicCount);
      if (currentSlots >= MAX_MESSAGES_PER_THREAD) {
        throw new HttpsError("resource-exhausted", "This note is full.");
      }

      const publishAt = validatePublishAt(publishAtMillis, nowMs, placeSnap);
      const isImmediate = publishAt.toMillis() <= nowMs;
      publishedImmediately = isImmediate;
      const nextSlots = currentSlots + 1;

      const placeUpdate: Record<string, unknown> = {};
      if (isImmediate) {
        const nextPublicCount = publicCount + 1;
        placeUpdate.messageCount = nextPublicCount;

        const lastMessageAt =
          placeSnap.get("lastMessageAt") as Timestamp | undefined;
        if (
          !lastMessageAt ||
          lastMessageAt.toMillis() < publishAt.toMillis()
        ) {
          placeUpdate.lastMessageAt = publishAt;
        }

        if (nextPublicCount >= MAX_MESSAGES_PER_THREAD) {
          placeUpdate.isOpen = false;
          placeUpdate.closedReason = "messageLimit";
          placeUpdate.closedAt = FieldValue.serverTimestamp();
        }
      }

      tx.set(
        counterRef,
        {
          count: nextSlots,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      if (Object.keys(placeUpdate).length > 0) {
        tx.update(placeRef, placeUpdate);
      }
      tx.set(messageRef, {
        placeId,
        userId: uid,
        userName: profile.displayName ?? "Unknown user",
        userPhotoUrl: photoUrlFor(req.auth?.token.picture),
        content: trimmedContent,
        ...(trimmedImageUrl ? {imageUrl: trimmedImageUrl} : {}),
        createdAt: FieldValue.serverTimestamp(),
        publishAt,
        placeAggregateAppliedAt: isImmediate ?
          FieldValue.serverTimestamp() :
          null,
        isDeleted: false,
        isVisible: true,
        isPubliclyVisible: isImmediate,
        reportCount: 0,
      });
    });

    if (publishedImmediately) {
      try {
        await sendMyNotesMessageNotifications(db, placeId, messageRef.id, uid);
      } catch (error) {
        logger.error(
          "sendMessage: failed to send My Notes notification for " +
            `places/${placeId}/messages/${messageRef.id}.`,
          error,
        );
      }
      try {
        await sendNearbyInRangeMessageNotifications(
          db,
          placeId,
          messageRef.id,
          uid,
        );
      } catch (error) {
        logger.error(
          "sendMessage: failed to send nearby notification for " +
            `places/${placeId}/messages/${messageRef.id}.`,
          error,
        );
      }
    }

    return {
      messageId: messageRef.id,
      publishAtMillis:
        typeof publishAtMillis === "number" ? publishAtMillis : nowMs,
    };
  },
);

/**
 * Cancels an unpublished scheduled message and frees its reserved slot.
 */
export const cancelScheduledMessage = onCall<CancelScheduledMessageData>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const {placeId, messageId} = req.data ?? {};
    if (typeof placeId !== "string" || placeId.length === 0) {
      throw new HttpsError("invalid-argument", "placeId is required.");
    }
    if (typeof messageId !== "string" || messageId.length === 0) {
      throw new HttpsError("invalid-argument", "messageId is required.");
    }

    const db = getFirestore();
    const placeRef = db.collection("places").doc(placeId);
    const counterRef = placeRef.collection("counters").doc("messageSlots");
    const messageRef = placeRef.collection("messages").doc(messageId);
    const nowMs = Date.now();

    await db.runTransaction(async (tx) => {
      const [placeSnap, messageSnap, counterSnap] = await Promise.all([
        tx.get(placeRef),
        tx.get(messageRef),
        tx.get(counterRef),
      ]);
      if (!placeSnap.exists || !messageSnap.exists) {
        throw new HttpsError("not-found", "Message not found.");
      }
      if (messageSnap.get("userId") !== uid) {
        throw new HttpsError(
          "permission-denied",
          "You can cancel only your own message.",
        );
      }
      if (messageSnap.get("isDeleted") === true) return;
      if (messageSnap.get("isPubliclyVisible") === true) {
        throw new HttpsError(
          "failed-precondition",
          "Published messages cannot be canceled.",
        );
      }

      const publishAt = messageSnap.get("publishAt") as Timestamp | undefined;
      if (!publishAt || publishAt.toMillis() <= nowMs) {
        throw new HttpsError(
          "failed-precondition",
          "This message is already due for publication.",
        );
      }

      const publicCount =
        (placeSnap.get("messageCount") as number | undefined) ?? 0;
      const currentSlots = messageSlotCount(counterSnap, publicCount);
      const nextSlots = Math.max(0, currentSlots - 1);
      tx.set(
        counterRef,
        {
          count: nextSlots,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );

      const placeUpdate: Record<string, unknown> = {};
      const expiresAt = placeSnap.get("expiresAt") as Timestamp | undefined;
      if (
        publicCount < MAX_MESSAGES_PER_THREAD &&
        nextSlots < MAX_MESSAGES_PER_THREAD &&
        placeSnap.get("closedReason") === "messageLimit" &&
        placeSnap.get("isArchived") !== true &&
        (!expiresAt || expiresAt.toMillis() > nowMs)
      ) {
        placeUpdate.isOpen = true;
        placeUpdate.closedReason = FieldValue.delete();
        placeUpdate.closedAt = FieldValue.delete();
      }

      if (Object.keys(placeUpdate).length > 0) {
        tx.update(placeRef, placeUpdate);
      }
      tx.delete(messageRef);
    });

    return {ok: true};
  },
);
