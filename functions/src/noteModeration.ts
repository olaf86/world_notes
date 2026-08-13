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
  detectAppModerationRiskSignals,
  hasReviewRecommendedRiskSignal,
  moderationAuditFields,
  moderateContent,
} from "./moderation";
import {
  type ModerationJobContext,
  type ModerationJobHandler,
} from "./moderationJobs";
import {enqueueHiddenNoteRetention} from "./noteModerationRetention";
import {worldContext} from "./platform/worldContext";

export const EVALUATE_NOTE_MODERATION_JOB = "evaluateNoteModeration";

export interface NoteModerationTextInput {
  readonly title: string;
  readonly subtitle: string | null;
}

interface NoteModerationTarget {
  readonly placeId: string;
}

interface NoteModerationReviewInput extends NoteModerationTextInput {
  readonly worldId: string;
  readonly uid: string;
  readonly placeId: string;
  readonly moderationResult: InternalModerationResult;
  readonly riskSignals: AppModerationRiskSignal[];
  readonly reviewExists: boolean;
}

interface NoteModerationFinalization {
  readonly action: string;
  readonly uid: string | null;
  readonly placeId: string;
}

/** Binds a moderation result to immutable submitted note text. */
export function noteModerationInputHash(
  title: string,
  subtitle: string | null,
): string {
  return createHash("sha256")
    .update(JSON.stringify([title, subtitle]), "utf8")
    .digest("hex");
}

/** Returns the active-note counter change for a manual moderation action. */
export function noteModerationActiveCountDelta(input: Readonly<{
  isArchived: boolean;
  activeNoteSlotReleased: boolean;
  hide: boolean;
}>): -1 | 0 | 1 {
  if (input.isArchived) return 0;
  if (input.hide) return input.activeNoteSlotReleased ? 0 : -1;
  return input.activeNoteSlotReleased ? 1 : 0;
}

function noteModerationText(input: NoteModerationTextInput): string {
  return [
    `Title: ${input.title}`,
    ...(input.subtitle === null ? [] : [`Description: ${input.subtitle}`]),
  ].join("\n");
}

function noteModerationTarget(targetPath: string): NoteModerationTarget {
  const segments = targetPath.split("/");
  if (segments.length !== 2 || segments[0] !== "places" ||
      segments[1].length === 0) {
    throw new Error("Note moderation target path is invalid.");
  }
  return Object.freeze({placeId: segments[1]});
}

function requireMatchingNoteModerationInput(
  place: DocumentSnapshot,
  expectedHash: string,
): NoteModerationTextInput {
  const title = place.get("title");
  const subtitle = place.get("subtitle");
  if (typeof title !== "string" || title.length === 0 ||
      (subtitle !== null && typeof subtitle !== "string") ||
      place.get("moderationInputHash") !== expectedHash ||
      noteModerationInputHash(title, subtitle) !== expectedHash) {
    const error = new Error("Note moderation input changed.");
    Object.assign(error, {code: "moderation/input-changed"});
    throw error;
  }
  return Object.freeze({title, subtitle});
}

function shouldCreateNoteModerationReview(
  moderationResult: InternalModerationResult,
  riskSignals: AppModerationRiskSignal[],
): boolean {
  return (moderationResult.action !== "allow" &&
      moderationResult.action !== "pending") ||
    hasReviewRecommendedRiskSignal(riskSignals);
}

function noteModerationReviewData(
  input: NoteModerationReviewInput,
): Record<string, unknown> {
  const reviewSources = [
    ...(input.moderationResult.action !== "allow" &&
      input.moderationResult.action !== "pending" ?
      ["provider" as const] : []),
    ...(hasReviewRecommendedRiskSignal(input.riskSignals) ?
      ["riskSignal" as const] : []),
  ];
  return {
    worldId: input.worldId,
    userId: input.uid,
    targetType: "note",
    targetId: input.placeId,
    targetPath: `places/${input.placeId}`,
    placeId: input.placeId,
    content: [input.title, input.subtitle]
      .filter((value): value is string => value !== null)
      .join("\n"),
    contentFields: {title: input.title, subtitle: input.subtitle},
    imageStoragePaths: [],
    reviewSources: FieldValue.arrayUnion(...reviewSources),
    ...(input.riskSignals.length > 0 ?
      {riskSignals: input.riskSignals} : {}),
    status: "open",
    ...(!input.reviewExists ?
      {createdAt: FieldValue.serverTimestamp()} : {}),
    ...moderationAuditFields(input.moderationResult),
  };
}

async function applyHiddenNoteSafety(
  context: ModerationJobContext,
  uid: string,
  placeId: string,
): Promise<void> {
  const homeAssignment = await context.firestore
    .collection("userHomes")
    .doc(uid)
    .get();
  const homeWorld = homeAssignment.get("world");
  if (!homeAssignment.exists || typeof homeWorld !== "string") {
    const error = new Error("Note creator home assignment is missing.");
    Object.assign(error, {code: "moderation/home-missing"});
    throw error;
  }
  await executeAccountSafetyEvent({
    firestore: worldContext(homeWorld).firestore,
    authorityWorld: homeWorld,
    uid,
    operationId: derivedGlobalOperationId(
      placeId,
      `hidden-note-account-safety:${context.jobId}`,
    ),
    eventId: `noteModeration:${context.jobId}`,
    points: ACCOUNT_SAFETY_HIDDEN_CONTENT_POINTS,
    sourceWorld: context.job.world,
    sourceType: "noteModerationHidden",
    sourceEntityId: placeId,
  });
}

async function applyAndRecordHiddenNoteSafety(
  context: ModerationJobContext,
  uid: string,
  placeId: string,
): Promise<void> {
  await applyHiddenNoteSafety(context, uid, placeId);
  const placeRef = context.firestore.collection("places").doc(placeId);
  await context.firestore.runTransaction(async (transaction) => {
    const place = await transaction.get(placeRef);
    if (!place.exists ||
        place.get("moderationHiddenJobId") !== context.jobId ||
        place.get("moderationSafetyAppliedAt") instanceof Timestamp) {
      return;
    }
    transaction.update(placeRef, {
      moderationSafetyAppliedAt: FieldValue.serverTimestamp(),
    });
  });
}

async function finalizeNoteModeration(
  context: ModerationJobContext,
  moderationResult: InternalModerationResult,
): Promise<NoteModerationFinalization> {
  const target = noteModerationTarget(context.job.targetPath);
  const placeRef = context.firestore.doc(context.job.targetPath);
  const reviewRef = context.firestore
    .collection("moderationReviews")
    .doc(`note_${target.placeId}`);

  return context.firestore.runTransaction(async (transaction) => {
    const place = await transaction.get(placeRef);
    if (!place.exists) {
      return {action: "missing", uid: null, placeId: target.placeId};
    }
    const uid = place.get("createdByUserId");
    if (typeof uid !== "string" || uid.length === 0) {
      throw new Error("Note moderation creator is invalid.");
    }
    const currentAction = place.get("moderationAction");
    if (currentAction !== "pending" || place.get("isArchived") === true) {
      return {action: String(currentAction), uid, placeId: target.placeId};
    }
    const submitted = requireMatchingNoteModerationInput(
      place,
      context.job.inputHash,
    );
    const riskSignals = detectAppModerationRiskSignals(
      noteModerationText(submitted),
    );
    const hidden = moderationResult.action === "hidden";
    const reviewRequired = moderationResult.action === "review" || hidden ||
      hasReviewRecommendedRiskSignal(riskSignals);
    const createReview = shouldCreateNoteModerationReview(
      moderationResult,
      riskSignals,
    );
    const usageRef = context.firestore.collection("userUsage").doc(uid);
    const [review, usage] = await Promise.all([
      createReview ? transaction.get(reviewRef) : Promise.resolve(null),
      hidden ? transaction.get(usageRef) : Promise.resolve(null),
    ]);
    const checkedAt = Timestamp.now();
    const update: Record<string, unknown> = {
      moderationAction: moderationResult.action,
      moderationProvider: moderationResult.provider,
      moderationPolicyVersion: moderationResult.policyVersion,
      moderationCheckedAt: checkedAt,
      isModerationHidden: hidden,
      isSensitive: moderationResult.action === "sensitive" ||
        moderationResult.action === "review",
      reviewRequired,
    };
    if (hidden) {
      const activeCount = nonNegativeNoteCount(
        usage?.get("activeNoteCount"),
        "activeNoteCount",
      );
      if (activeCount === 0 ||
          place.get("activeNoteSlotReleasedAt") !== null) {
        throw new Error("Note moderation active-slot state is invalid.");
      }
      update.isOpen = false;
      update.wasOpenBeforeModeration = place.get("isOpen") === true;
      update.activeNoteSlotReleasedAt = checkedAt;
      update.moderationHiddenAt = checkedAt;
      update.moderationPurgeStartedAt = null;
      update.moderationHiddenJobId = context.jobId;
      update.moderationSafetyAppliedAt = null;
      transaction.set(usageRef, {
        activeNoteCount: activeCount - 1,
        updatedAt: checkedAt,
      }, {merge: true});
      enqueueHiddenNoteRetention(transaction, context.firestore, {
        world: context.job.world,
        placeId: target.placeId,
        hiddenAt: checkedAt,
      });
    }
    transaction.update(placeRef, update);
    if (createReview) {
      transaction.set(reviewRef, noteModerationReviewData({
        worldId: context.job.world,
        uid,
        placeId: target.placeId,
        ...submitted,
        moderationResult,
        riskSignals,
        reviewExists: review?.exists === true,
      }), {merge: true});
    }
    return {action: moderationResult.action, uid, placeId: target.placeId};
  });
}

function nonNegativeNoteCount(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw new Error(`Note ${field} is invalid.`);
  }
  return value;
}

/** Evaluates and finalizes one optimistic note without stale overwrite. */
export const noteModerationJobHandler: ModerationJobHandler = {
  jobType: EVALUATE_NOTE_MODERATION_JOB,
  async process(context): Promise<void> {
    const target = noteModerationTarget(context.job.targetPath);
    const place = await context.firestore.doc(context.job.targetPath).get();
    if (!place.exists) return;
    const uid = place.get("createdByUserId");
    if (typeof uid !== "string" || uid.length === 0) {
      throw new Error("Note moderation creator is invalid.");
    }
    const currentAction = place.get("moderationAction");
    if (place.get("moderationHiddenJobId") === context.jobId &&
        !(place.get("moderationSafetyAppliedAt") instanceof Timestamp)) {
      await applyAndRecordHiddenNoteSafety(context, uid, target.placeId);
      return;
    }
    if (currentAction === "hidden") return;
    if (currentAction !== "pending" || place.get("isArchived") === true) {
      return;
    }
    const submitted = requireMatchingNoteModerationInput(
      place,
      context.job.inputHash,
    );
    const result = await moderateContent(noteModerationText(submitted));
    if (result.action === "pending") {
      const error = new Error(
        "Moderation provider is temporarily unavailable.",
      );
      Object.assign(error, {code: "moderation/provider-unavailable"});
      throw error;
    }
    const finalized = await finalizeNoteModeration(context, result);
    if (finalized.action === "hidden" && finalized.uid !== null) {
      await applyAndRecordHiddenNoteSafety(
        context,
        finalized.uid,
        finalized.placeId,
      );
    }
  },
};
