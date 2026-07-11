/* eslint-disable require-jsdoc */
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {
  FieldValue,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import * as logger from "firebase-functions/logger";

import {REGION} from "./constants";

type AdminModerationAction = "allow" | "sensitive" | "hidden";

interface AdminReviewMessageData {
  placeId?: unknown;
  messageId?: unknown;
  action?: unknown;
  reason?: unknown;
}

interface ValidatedAdminReviewMessageInput {
  placeId: string;
  messageId: string;
  action: AdminModerationAction;
  reason: string | null;
}

function assertAdmin(uid: string | undefined, adminClaim: unknown) {
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  if (adminClaim !== true) {
    throw new HttpsError("permission-denied", "Admin only.");
  }
}

function requiredString(value: unknown, fieldName: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${fieldName} is required.`);
  }
  return value.trim();
}

function adminModerationAction(value: unknown): AdminModerationAction {
  if (value === "allow" || value === "sensitive" || value === "hidden") {
    return value;
  }
  throw new HttpsError("invalid-argument", "Invalid moderation action.");
}

function optionalReason(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "reason must be a string.");
  }
  const trimmed = value.trim();
  if (trimmed.length > 500) {
    throw new HttpsError("invalid-argument", "reason is too long.");
  }
  return trimmed.length > 0 ? trimmed : null;
}

function validateAdminReviewMessageInput(
  data: AdminReviewMessageData | undefined,
): ValidatedAdminReviewMessageInput {
  return {
    placeId: requiredString(data?.placeId, "placeId"),
    messageId: requiredString(data?.messageId, "messageId"),
    action: adminModerationAction(data?.action),
    reason: optionalReason(data?.reason),
  };
}

function storedImagePaths(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((path): path is string => typeof path === "string");
}

function restoredContentFor(
  reviewContent: unknown,
  currentContent: unknown,
): string {
  if (typeof reviewContent === "string") return reviewContent;
  return typeof currentContent === "string" ? currentContent : "";
}

function messageUpdateForAction({
  action,
  reviewContent,
  currentContent,
}: {
  action: AdminModerationAction;
  reviewContent: unknown;
  currentContent: unknown;
}): Record<string, unknown> {
  const base: Record<string, unknown> = {
    moderationAction: action,
    moderationReviewedAt: FieldValue.serverTimestamp(),
    reviewRequired: false,
    isVisible: true,
  };
  switch (action) {
  case "allow":
    return {
      ...base,
      content: restoredContentFor(reviewContent, currentContent),
      isDeleted: false,
      deletedAt: null,
      deletedReason: null,
      isSensitive: false,
    };
  case "sensitive":
    return {
      ...base,
      content: restoredContentFor(reviewContent, currentContent),
      isDeleted: false,
      deletedAt: null,
      deletedReason: null,
      isSensitive: true,
    };
  case "hidden":
    return {
      ...base,
      content: "",
      imageStoragePaths: FieldValue.delete(),
      isDeleted: true,
      deletedAt: FieldValue.serverTimestamp(),
      deletedReason: "moderation",
      isSensitive: false,
    };
  }
}

async function deleteStoredImages(storagePaths: string[]): Promise<void> {
  if (storagePaths.length === 0) return;
  const bucket = getStorage().bucket();
  await Promise.all(storagePaths.map(async (storagePath) => {
    try {
      await bucket.file(storagePath).delete({ignoreNotFound: true});
    } catch (error) {
      logger.warn(`Could not delete moderated image ${storagePath}.`, error);
    }
  }));
}

/**
 * Applies a trusted administrator moderation decision to a queued message.
 */
export const adminReviewMessage = onCall<AdminReviewMessageData>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const token = req.auth?.token as Record<string, unknown> | undefined;
    assertAdmin(req.auth?.uid, token?.admin);
    const uid = req.auth?.uid as string;
    const input = validateAdminReviewMessageInput(req.data);
    const db = getFirestore();
    const placeRef = db.collection("places").doc(input.placeId);
    const messageRef = placeRef.collection("messages").doc(input.messageId);
    const reviewRef = db
      .collection("moderationReviews")
      .doc(`${input.placeId}_${input.messageId}`);
    const auditRef = db.collection("moderationAuditLogs").doc();
    let imageStoragePathsToDelete: string[] = [];

    await db.runTransaction(async (tx) => {
      const [messageSnap, reviewSnap] = await Promise.all([
        tx.get(messageRef),
        tx.get(reviewRef),
      ]);
      if (!messageSnap.exists) {
        throw new HttpsError("not-found", "Message not found.");
      }
      if (!reviewSnap.exists) {
        throw new HttpsError("not-found", "Moderation review not found.");
      }
      const deletedReason = messageSnap.get("deletedReason") as
        string | null | undefined;
      if (
        input.action !== "hidden" &&
        messageSnap.get("isDeleted") === true &&
        deletedReason !== "moderation"
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Author-deleted messages cannot be restored by moderation review.",
        );
      }

      if (input.action === "hidden") {
        imageStoragePathsToDelete = storedImagePaths(
          messageSnap.get("imageStoragePaths"),
        );
      }

      tx.update(messageRef, {
        ...messageUpdateForAction({
          action: input.action,
          reviewContent: reviewSnap.get("content"),
          currentContent: messageSnap.get("content"),
        }),
        moderationReviewedBy: uid,
        moderationReviewReason: input.reason,
      });
      tx.update(reviewRef, {
        status: "resolved",
        humanDecision: input.action,
        decisionReason: input.reason,
        reviewedAt: FieldValue.serverTimestamp(),
        reviewedBy: uid,
        messagePath: `places/${input.placeId}/messages/${input.messageId}`,
      });
      tx.set(auditRef, {
        adminUserId: uid,
        placeId: input.placeId,
        messageId: input.messageId,
        messagePath: `places/${input.placeId}/messages/${input.messageId}`,
        reviewPath: `moderationReviews/${reviewRef.id}`,
        action: input.action,
        reason: input.reason,
        previousModerationAction: messageSnap.get("moderationAction") ?? null,
        previousIsDeleted: messageSnap.get("isDeleted") ?? null,
        previousDeletedReason: deletedReason ?? null,
        previousIsSensitive: messageSnap.get("isSensitive") ?? null,
        createdAt: FieldValue.serverTimestamp(),
      });
    });

    await deleteStoredImages(imageStoragePathsToDelete);
    return {
      ok: true,
      placeId: input.placeId,
      messageId: input.messageId,
      action: input.action,
      reviewedAtMillis: Timestamp.now().toMillis(),
    };
  },
);
