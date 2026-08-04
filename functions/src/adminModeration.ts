/* eslint-disable require-jsdoc */
import {onCall, HttpsError} from "./platform/worldCallable";
import {
  FieldValue,
  Timestamp,
} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

import {REGION} from "./constants";
import {WorldBucket} from "./platform/worldBucketProvider";

const DEFAULT_REVIEW_LIST_LIMIT = 20;
const MAX_REVIEW_LIST_LIMIT = 50;

type AdminModerationAction = "allow" | "sensitive" | "hidden";
type AdminModerationReviewStatus = "open" | "resolved";

interface AdminListModerationReviewsData {
  limit?: unknown;
  status?: unknown;
}

interface AdminReviewMessageData {
  placeId?: unknown;
  messageId?: unknown;
  action?: unknown;
  reason?: unknown;
}

interface AdminReviewNoteData {
  placeId?: unknown;
  action?: unknown;
  reason?: unknown;
}

interface ValidatedAdminReviewMessageInput {
  placeId: string;
  messageId: string;
  action: AdminModerationAction;
  reason: string | null;
}

interface ValidatedAdminReviewNoteInput {
  placeId: string;
  action: AdminModerationAction;
  reason: string | null;
}

interface ValidatedAdminListModerationReviewsInput {
  limit: number;
  status: AdminModerationReviewStatus;
}

function assertAdmin(uid: string | undefined, adminClaim: unknown) {
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  if (adminClaim !== true) {
    throw new HttpsError("permission-denied", "Admin only.");
  }
}

function validateLimit(value: unknown): number {
  if (value == null) return DEFAULT_REVIEW_LIST_LIMIT;
  if (typeof value !== "number" || !Number.isInteger(value)) {
    throw new HttpsError("invalid-argument", "limit must be an integer.");
  }
  if (value < 1 || value > MAX_REVIEW_LIST_LIMIT) {
    throw new HttpsError(
      "invalid-argument",
      `limit must be 1-${MAX_REVIEW_LIST_LIMIT}.`,
    );
  }
  return value;
}

function reviewStatus(value: unknown): AdminModerationReviewStatus {
  if (value == null || value === "open") return "open";
  if (value === "resolved") return "resolved";
  throw new HttpsError("invalid-argument", "Invalid review status.");
}

function validateAdminListModerationReviewsInput(
  data: AdminListModerationReviewsData | undefined,
): ValidatedAdminListModerationReviewsInput {
  return {
    limit: validateLimit(data?.limit),
    status: reviewStatus(data?.status),
  };
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

function validateAdminReviewNoteInput(
  data: AdminReviewNoteData | undefined,
): ValidatedAdminReviewNoteInput {
  const action = adminModerationAction(data?.action);
  if (action === "sensitive") {
    throw new HttpsError(
      "invalid-argument",
      "Notes can only be allowed or hidden.",
    );
  }
  return {
    placeId: requiredString(data?.placeId, "placeId"),
    action,
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

function timestampMillis(value: unknown): number | null {
  return value instanceof Timestamp ? value.toMillis() : null;
}

function reviewListItemFromDoc(
  doc: FirebaseFirestore.QueryDocumentSnapshot,
  worldId: string,
): Record<string, unknown> {
  const data = doc.data();
  return {
    id: doc.id,
    worldId,
    targetType: data.targetType ?? null,
    targetId: data.targetId ?? null,
    targetPath: data.targetPath ?? null,
    userId: data.userId ?? null,
    placeId: data.placeId ?? null,
    content: data.content ?? "",
    imageStoragePaths: data.imageStoragePaths ?? [],
    status: data.status ?? null,
    reviewSources: data.reviewSources ?? [],
    reportCount: data.reportCount ?? null,
    reportReasonsSummary: data.reportReasonsSummary ?? [],
    riskSignals: data.riskSignals ?? [],
    action: data.action ?? null,
    maxScore: data.maxScore ?? null,
    categories: data.categories ?? [],
    provider: data.provider ?? null,
    providerModel: data.providerModel ?? null,
    policyVersion: data.policyVersion ?? null,
    flagged: data.flagged ?? null,
    providerResultId: data.providerResultId ?? null,
    createdAtMillis: timestampMillis(data.createdAt),
    checkedAtMillis: timestampMillis(data.checkedAt),
    humanDecision: data.humanDecision ?? null,
    decisionReason: data.decisionReason ?? null,
    reviewedAtMillis: timestampMillis(data.reviewedAt),
    reviewedBy: data.reviewedBy ?? null,
  };
}

async function deleteStoredImages(
  bucket: WorldBucket,
  storagePaths: string[],
): Promise<void> {
  if (storagePaths.length === 0) return;
  await Promise.all(storagePaths.map(async (storagePath) => {
    try {
      await bucket.file(storagePath).delete({ignoreNotFound: true});
    } catch (error) {
      logger.warn(`Could not delete moderated image ${storagePath}.`, error);
    }
  }));
}

/**
 * Lists moderation review queue items for trusted administrators.
 */
export const adminListModerationReviews =
  onCall<AdminListModerationReviewsData>(
    {enforceAppCheck: true, region: REGION},
    async (req, world) => {
      const token = req.auth?.token as Record<string, unknown> | undefined;
      assertAdmin(req.auth?.uid, token?.admin);
      const input = validateAdminListModerationReviewsInput(req.data);
      const snap = await world.firestore
        .collection("moderationReviews")
        .where("status", "==", input.status)
        .orderBy("createdAt", "asc")
        .limit(input.limit)
        .get();

      return {
        status: input.status,
        reviews: snap.docs.map((doc) =>
          reviewListItemFromDoc(doc, world.worldId)),
      };
    },
  );

/**
 * Applies a trusted administrator moderation decision to a queued message.
 */
export const adminReviewMessage = onCall<AdminReviewMessageData>(
  {enforceAppCheck: true, region: REGION},
  async (req, world) => {
    const token = req.auth?.token as Record<string, unknown> | undefined;
    assertAdmin(req.auth?.uid, token?.admin);
    const uid = req.auth?.uid as string;
    const input = validateAdminReviewMessageInput(req.data);
    const db = world.firestore;
    const placeRef = db.collection("places").doc(input.placeId);
    const messageRef = placeRef.collection("messages").doc(input.messageId);
    const reviewRef = db
      .collection("moderationReviews")
      .doc(`${input.placeId}_${input.messageId}`);
    const auditRef = db.collection("moderationAuditLogs").doc();
    let imageStoragePathsToDelete: string[] = [];
    const reportResolutionStatus =
      input.action === "allow" ? "rejected" : "accepted";

    await db.runTransaction(async (tx) => {
      const reportsQuery = db
        .collection("reports")
        .where("targetType", "==", "message")
        .where("targetId", "==", input.messageId)
        .where("status", "==", "open");
      const [messageSnap, reviewSnap, reportsSnap] = await Promise.all([
        tx.get(messageRef),
        tx.get(reviewRef),
        tx.get(reportsQuery),
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
        worldId: world.worldId,
        status: "resolved",
        humanDecision: input.action,
        decisionReason: input.reason,
        reviewedAt: FieldValue.serverTimestamp(),
        reviewedBy: uid,
        targetType: "message",
        targetId: input.messageId,
        targetPath: `places/${input.placeId}/messages/${input.messageId}`,
      });
      tx.set(auditRef, {
        worldId: world.worldId,
        eventType: "adminDecision",
        actorType: "admin",
        actorId: uid,
        subjectUserId: messageSnap.get("userId") ?? null,
        targetType: "message",
        targetId: input.messageId,
        targetPath: `places/${input.placeId}/messages/${input.messageId}`,
        placeId: input.placeId,
        reviewPath: `moderationReviews/${reviewRef.id}`,
        action: input.action,
        reason: input.reason,
        previousModerationAction: messageSnap.get("moderationAction") ?? null,
        previousIsDeleted: messageSnap.get("isDeleted") ?? null,
        previousDeletedReason: deletedReason ?? null,
        previousIsSensitive: messageSnap.get("isSensitive") ?? null,
        createdAt: FieldValue.serverTimestamp(),
      });
      reportsSnap.docs.forEach((reportDoc) => {
        tx.update(reportDoc.ref, {
          status: reportResolutionStatus,
          resolvedAt: FieldValue.serverTimestamp(),
          resolvedBy: uid,
          moderationReviewId: reviewRef.id,
          moderationDecision: input.action,
          moderationReason: input.reason,
        });
      });
    });

    await deleteStoredImages(world.bucket, imageStoragePathsToDelete);
    return {
      ok: true,
      placeId: input.placeId,
      messageId: input.messageId,
      action: input.action,
      reviewedAtMillis: Timestamp.now().toMillis(),
    };
  },
);

/**
 * Applies a trusted administrator moderation decision to a queued note.
 */
export const adminReviewNote = onCall<AdminReviewNoteData>(
  {enforceAppCheck: true, region: REGION},
  async (req, world) => {
    const token = req.auth?.token as Record<string, unknown> | undefined;
    assertAdmin(req.auth?.uid, token?.admin);
    const uid = req.auth?.uid as string;
    const input = validateAdminReviewNoteInput(req.data);
    const db = world.firestore;
    const placeRef = db.collection("places").doc(input.placeId);
    const reviewRef = db
      .collection("moderationReviews")
      .doc(`note_${input.placeId}`);
    const auditRef = db.collection("moderationAuditLogs").doc();
    const reportResolutionStatus =
      input.action === "allow" ? "rejected" : "accepted";

    await db.runTransaction(async (tx) => {
      const reportsQuery = db
        .collection("reports")
        .where("targetType", "==", "note")
        .where("targetId", "==", input.placeId)
        .where("status", "==", "open");
      const [placeSnap, reviewSnap, reportsSnap] = await Promise.all([
        tx.get(placeRef),
        tx.get(reviewRef),
        tx.get(reportsQuery),
      ]);
      if (!placeSnap.exists) {
        throw new HttpsError("not-found", "Note not found.");
      }
      if (!reviewSnap.exists) {
        throw new HttpsError("not-found", "Moderation review not found.");
      }

      const hidden = input.action !== "allow";
      tx.update(placeRef, {
        moderationAction: hidden ? "hidden" : "allow",
        isModerationHidden: hidden,
        reviewRequired: false,
        moderationReviewedAt: FieldValue.serverTimestamp(),
        moderationReviewedBy: uid,
        moderationReviewReason: input.reason,
      });
      tx.update(reviewRef, {
        worldId: world.worldId,
        status: "resolved",
        humanDecision: hidden ? "hidden" : "allow",
        decisionReason: input.reason,
        reviewedAt: FieldValue.serverTimestamp(),
        reviewedBy: uid,
        targetType: "note",
        targetId: input.placeId,
        targetPath: `places/${input.placeId}`,
      });
      tx.set(auditRef, {
        worldId: world.worldId,
        eventType: "adminDecision",
        actorType: "admin",
        actorId: uid,
        subjectUserId: placeSnap.get("createdByUserId") ?? null,
        targetType: "note",
        targetId: input.placeId,
        targetPath: `places/${input.placeId}`,
        placeId: input.placeId,
        reviewPath: `moderationReviews/${reviewRef.id}`,
        action: hidden ? "hidden" : "allow",
        reason: input.reason,
        previousModerationAction:
          placeSnap.get("moderationAction") ?? null,
        previousIsModerationHidden:
          placeSnap.get("isModerationHidden") ?? null,
        createdAt: FieldValue.serverTimestamp(),
      });
      reportsSnap.docs.forEach((reportDoc) => {
        tx.update(reportDoc.ref, {
          status: reportResolutionStatus,
          resolvedAt: FieldValue.serverTimestamp(),
          resolvedBy: uid,
          moderationReviewId: reviewRef.id,
          moderationDecision: hidden ? "hidden" : "allow",
          moderationReason: input.reason,
        });
      });
    });

    return {
      ok: true,
      placeId: input.placeId,
      action: input.action === "allow" ? "allow" : "hidden",
      reviewedAtMillis: Timestamp.now().toMillis(),
    };
  },
);
