/* eslint-disable require-jsdoc, valid-jsdoc */

import {createHash} from "node:crypto";

import {
  DocumentSnapshot,
  FieldValue,
  Timestamp,
} from "firebase-admin/firestore";

import {
  ACCOUNT_SAFETY_HIDDEN_CONTENT_POINTS,
  executeAccountSafetyEvent,
} from "./accountSafety";
import {derivedGlobalOperationId} from "./globalOperations";
import {
  type AppModerationRiskSignal,
  type InternalModerationResult,
  type ModerationImageInput,
  detectAppModerationRiskSignals,
  hasReviewRecommendedRiskSignal,
  moderationAuditFields,
  moderateContent,
} from "./moderation";
import {
  type ModerationJobContext,
  type ModerationJobHandler,
} from "./moderationJobs";
import {enqueueHiddenMessageRetention} from "./messageModerationRetention";
import {enqueueMyNotesMessageNotification} from "./notifications";
import {HttpsError} from "./platform/worldCallable";
import {WorldBucket} from "./platform/worldBucketProvider";
import {worldContext} from "./platform/worldContext";

export const EVALUATE_MESSAGE_MODERATION_JOB =
  "evaluateMessageModeration";

export interface MessageModerationInput {
  readonly content: string;
  readonly imageStoragePaths: readonly string[];
}

interface MessageModerationTarget {
  readonly placeId: string;
  readonly messageId: string;
}

interface MessageModerationReviewInput extends MessageModerationTarget {
  readonly uid: string;
  readonly worldId: string;
  readonly moderationResult: InternalModerationResult;
  readonly riskSignals: AppModerationRiskSignal[];
  readonly submitted: MessageModerationInput;
  readonly reviewExists: boolean;
}

interface MessageModerationFinalization {
  readonly action: string;
  readonly uid: string | null;
  readonly messageId: string;
}

type ModerationReviewSource = "provider" | "riskSignal";

const UUID_V7_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

/** Hashes the immutable content evaluated by a message moderation job. */
export function messageModerationInputHash(
  content: string,
  imageStoragePaths: readonly string[],
): string {
  return createHash("sha256")
    .update(JSON.stringify([content, imageStoragePaths]), "utf8")
    .digest("hex");
}

async function moderationImagesFor(
  bucket: WorldBucket,
  storagePaths: readonly string[],
): Promise<ModerationImageInput[]> {
  if (storagePaths.length === 0) return [];
  return Promise.all(storagePaths.map(async (storagePath) => {
    const file = bucket.file(storagePath);
    try {
      const [[metadata], [bytes]] = await Promise.all([
        file.getMetadata(),
        file.download(),
      ]);
      if (metadata.contentType !== "image/webp" ||
          Number(metadata.size ?? bytes.length) > 2 * 1024 * 1024) {
        throw new HttpsError(
          "invalid-argument",
          "Invalid message image metadata.",
          {reason: "invalid_image"},
        );
      }
      return {bytes, contentType: "image/webp" as const};
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError(
        "failed-precondition",
        "Message image upload was not found.",
        {reason: "image_upload_missing"},
      );
    }
  }));
}

function messageModerationTarget(
  targetPath: string,
): MessageModerationTarget {
  const segments = targetPath.split("/");
  if (segments.length !== 4 || segments[0] !== "places" ||
      segments[1].length === 0 || segments[1].includes("/") ||
      segments[2] !== "messages" || !UUID_V7_PATTERN.test(segments[3])) {
    throw new Error("Message moderation target path is invalid.");
  }
  return Object.freeze({placeId: segments[1], messageId: segments[3]});
}

function moderationInputFromMessage(
  message: DocumentSnapshot,
): MessageModerationInput {
  const content = message.get("content");
  const paths = message.get("imageStoragePaths");
  if (typeof content !== "string" ||
      (paths !== undefined &&
       (!Array.isArray(paths) ||
        paths.some((path) => typeof path !== "string")))) {
    throw new Error("Message moderation input is invalid.");
  }
  return Object.freeze({
    content,
    imageStoragePaths: Object.freeze(
      paths === undefined ? [] : [...paths] as string[],
    ),
  });
}

function requireMatchingModerationInput(
  message: DocumentSnapshot,
  expectedHash: string,
): MessageModerationInput {
  const input = moderationInputFromMessage(message);
  if (messageModerationInputHash(
    input.content,
    input.imageStoragePaths,
  ) !== expectedHash) {
    const error = new Error("Message moderation input changed.");
    Object.assign(error, {code: "moderation/input-changed"});
    throw error;
  }
  return input;
}

function moderationReviewDocumentData(
  input: MessageModerationReviewInput,
): Record<string, unknown> {
  const reviewSources: ModerationReviewSource[] = [
    ...(input.moderationResult.action !== "allow" &&
      input.moderationResult.action !== "pending" ?
      ["provider" as const] : []),
    ...(hasReviewRecommendedRiskSignal(input.riskSignals) ?
      ["riskSignal" as const] : []),
  ];
  return {
    worldId: input.worldId,
    userId: input.uid,
    targetType: "message",
    targetId: input.messageId,
    targetPath: `places/${input.placeId}/messages/${input.messageId}`,
    placeId: input.placeId,
    content: input.submitted.content,
    imageStoragePaths: input.submitted.imageStoragePaths,
    reviewSources: FieldValue.arrayUnion(...reviewSources),
    ...(input.riskSignals.length > 0 ?
      {riskSignals: input.riskSignals} : {}),
    status: "open",
    ...(!input.reviewExists ?
      {createdAt: FieldValue.serverTimestamp()} : {}),
    ...moderationAuditFields(input.moderationResult),
  };
}

function shouldCreateModerationReview(
  moderationResult: InternalModerationResult,
  riskSignals: AppModerationRiskSignal[],
): boolean {
  return (moderationResult.action !== "allow" &&
      moderationResult.action !== "pending") ||
    hasReviewRecommendedRiskSignal(riskSignals);
}

async function applyHiddenMessageSafety(
  context: ModerationJobContext,
  uid: string,
  messageId: string,
): Promise<void> {
  const home = await context.firestore.collection("userHomes").doc(uid).get();
  const homeWorld = home.get("world");
  if (!home.exists || typeof homeWorld !== "string") {
    const error = new Error("Message sender home assignment is missing.");
    Object.assign(error, {code: "moderation/home-missing"});
    throw error;
  }
  await executeAccountSafetyEvent({
    firestore: worldContext(homeWorld).firestore,
    authorityWorld: homeWorld,
    uid,
    operationId: derivedGlobalOperationId(
      messageId,
      `hidden-message-account-safety:${context.jobId}`,
    ),
    eventId: `messageModeration:${context.jobId}`,
    points: ACCOUNT_SAFETY_HIDDEN_CONTENT_POINTS,
    sourceWorld: context.job.world,
    sourceType: "messageModerationHidden",
    sourceEntityId: messageId,
  });
}

async function finalizeMessageModeration(
  context: ModerationJobContext,
  moderationResult: InternalModerationResult,
): Promise<MessageModerationFinalization> {
  const target = messageModerationTarget(context.job.targetPath);
  const messageRef = context.firestore.doc(context.job.targetPath);
  const placeRef = context.firestore.collection("places").doc(target.placeId);
  const reviewRef = context.firestore
    .collection("moderationReviews")
    .doc(`${target.placeId}_${target.messageId}`);

  return context.firestore.runTransaction(async (transaction) => {
    const [message, place] = await Promise.all([
      transaction.get(messageRef),
      transaction.get(placeRef),
    ]);
    if (!message.exists) {
      return {action: "missing", uid: null, messageId: target.messageId};
    }
    const uid = message.get("userId");
    if (typeof uid !== "string") {
      throw new Error("Message moderation user is invalid.");
    }
    const currentAction = message.get("moderationAction");
    if (currentAction !== "pending" || message.get("isDeleted") === true) {
      return {action: String(currentAction), uid, messageId: target.messageId};
    }
    const submitted = requireMatchingModerationInput(
      message,
      context.job.inputHash,
    );
    if (!place.exists) {
      throw new Error("Message moderation parent note is missing.");
    }

    const checkedAt = Timestamp.now();
    const hidden = moderationResult.action === "hidden";
    const riskSignals = detectAppModerationRiskSignals(submitted.content);
    const reviewRequired = moderationResult.action === "review" || hidden ||
      hasReviewRecommendedRiskSignal(riskSignals);
    const createReview = shouldCreateModerationReview(
      moderationResult,
      riskSignals,
    );
    const review = createReview ? await transaction.get(reviewRef) : null;
    const update: Record<string, unknown> = {
      moderationAction: moderationResult.action,
      moderationPolicyVersion: moderationResult.policyVersion,
      moderationCheckedAt: checkedAt,
      isSensitive: moderationResult.action === "sensitive" ||
        moderationResult.action === "review",
      isVisible: !hidden,
      reviewRequired,
    };

    if (hidden) {
      update.isDeleted = true;
      update.deletedAt = checkedAt;
      update.deletedReason = "moderation";
      update.moderationPurgeStartedAt = null;
      update.moderationRestorePubliclyVisible =
        message.get("isPubliclyVisible") === true;
      update.isPubliclyVisible = false;
      enqueueHiddenMessageRetention(transaction, context.firestore, {
        world: context.job.world,
        placeId: target.placeId,
        messageId: target.messageId,
        hiddenAt: checkedAt,
      });
      if (message.get("placeAggregateAppliedAt") != null) {
        const currentCount = messageCountOf(place.get("messageCount"));
        transaction.update(placeRef, {
          messageCount: Math.max(0, currentCount - 1),
        });
      }
    } else if (message.get("isPubliclyVisible") === true) {
      const administrators = await transaction.get(
        placeRef.collection("administrators"),
      );
      enqueueMyNotesMessageNotification(transaction, context.firestore, {
        sourceWorld: context.job.world,
        place,
        administratorUids: administrators.docs
          .filter((document) => document.get("userId") === document.id)
          .map((document) => document.id),
        messageId: target.messageId,
        senderId: uid,
        createdAt: checkedAt,
      });
    }

    transaction.update(messageRef, update);
    if (createReview) {
      transaction.set(reviewRef, moderationReviewDocumentData({
        uid,
        worldId: context.job.world,
        ...target,
        moderationResult,
        riskSignals,
        submitted,
        reviewExists: review?.exists === true,
      }), {merge: true});
    }
    return {action: moderationResult.action, uid, messageId: target.messageId};
  });
}

function messageCountOf(value: unknown): number {
  if (value === undefined) return 0;
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw new Error("Message count is invalid.");
  }
  return value;
}

/** Evaluates and finalizes one optimistic message without stale overwrite. */
export const messageModerationJobHandler: ModerationJobHandler = {
  jobType: EVALUATE_MESSAGE_MODERATION_JOB,
  async process(context): Promise<void> {
    const target = messageModerationTarget(context.job.targetPath);
    const message = await context.firestore.doc(context.job.targetPath).get();
    if (!message.exists) return;
    const uid = message.get("userId");
    if (typeof uid !== "string") {
      throw new Error("Message moderation user is invalid.");
    }
    const currentAction = message.get("moderationAction");
    if (currentAction === "hidden") {
      await applyHiddenMessageSafety(context, uid, target.messageId);
      return;
    }
    if (currentAction !== "pending" || message.get("isDeleted") === true) {
      return;
    }
    const submitted = requireMatchingModerationInput(
      message,
      context.job.inputHash,
    );
    const images = await moderationImagesFor(
      worldContext(context.job.world).bucket,
      submitted.imageStoragePaths,
    );
    const result = await moderateContent(submitted.content, images);
    if (result.action === "pending") {
      const error = new Error(
        "Moderation provider is temporarily unavailable.",
      );
      Object.assign(error, {code: "moderation/provider-unavailable"});
      throw error;
    }
    const finalized = await finalizeMessageModeration(context, result);
    if (finalized.action === "hidden" && finalized.uid !== null) {
      await applyHiddenMessageSafety(
        context,
        finalized.uid,
        finalized.messageId,
      );
    }
  },
};
