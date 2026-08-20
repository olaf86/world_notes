/* eslint-disable require-jsdoc, valid-jsdoc */

import {
  FieldValue,
  Timestamp,
} from "firebase-admin/firestore";

import {
  ACCOUNT_SAFETY_HIDDEN_CONTENT_POINTS,
  executeAccountSafetyEvent,
} from "./accountSafety";
import {derivedGlobalOperationId} from "./globalOperations";
import {imageUploadId} from "./imageUploads";
import {
  type InternalModerationResult,
  type ModerationAction,
  moderationAuditFields,
  moderateContent,
} from "./moderation";
import {
  type ModerationJobContext,
  type ModerationJobHandler,
} from "./moderationJobs";
import {
  parsePinImageCandidate,
  pinImageCandidateId,
  type PinImageCandidateData,
} from "./pinImageCandidate";
import {worldContext} from "./platform/worldContext";
import {enqueueStorageObjectDeletion} from "./storageObjectCleanup";

export const EVALUATE_PIN_IMAGE_MODERATION_JOB =
  "evaluatePinImageModeration";
export const PIN_IMAGE_MODERATION_AUDIT_RETENTION_MILLIS =
  365 * 24 * 60 * 60 * 1000;

interface PinImageModerationTarget {
  readonly placeId: string;
}

const PIN_IMAGE_MODERATION_FINALIZATION_STATUS = Object.freeze({
  accepted: "accepted",
  rejected: "rejected",
  superseded: "superseded",
} as const);

const PIN_IMAGE_MODERATION_SUPERSEDED_REASON = Object.freeze({
  targetMissing: "targetMissing",
  candidateMissing: "candidateMissing",
  candidateChanged: "candidateChanged",
} as const);

type PinImageModerationRejectionAction = Exclude<
  ModerationAction,
  "allow" | "pending"
>;

type PinImageModerationRejectionResult = InternalModerationResult & Readonly<{
  action: PinImageModerationRejectionAction;
}>;

type PinImageModerationFinalization =
  | Readonly<{
    status: typeof PIN_IMAGE_MODERATION_FINALIZATION_STATUS.accepted;
  }>
  | Readonly<{
    status: typeof PIN_IMAGE_MODERATION_FINALIZATION_STATUS.rejected;
    action: PinImageModerationRejectionAction;
  }>
  | Readonly<{
    status: typeof PIN_IMAGE_MODERATION_FINALIZATION_STATUS.superseded;
    reason: typeof PIN_IMAGE_MODERATION_SUPERSEDED_REASON[
      keyof typeof PIN_IMAGE_MODERATION_SUPERSEDED_REASON
    ];
  }>;

interface PinImageModerationAuditInput {
  readonly context: ModerationJobContext;
  readonly target: PinImageModerationTarget;
  readonly candidate: PinImageCandidateData;
  readonly candidateId: string;
  readonly result: PinImageModerationRejectionResult;
  readonly checkedAt: Timestamp;
}

function pinImageModerationTarget(
  targetPath: string,
): PinImageModerationTarget {
  const segments = targetPath.split("/");
  if (segments.length !== 2 || segments[0] !== "places" ||
      segments[1].length === 0) {
    throw new Error("Pin image moderation target path is invalid.");
  }
  return Object.freeze({placeId: segments[1]});
}

function pinImageModerationAuditData(
  input: PinImageModerationAuditInput,
): Record<string, unknown> {
  return {
    worldId: input.context.job.world,
    eventType: "automatedRejection",
    actorType: "provider",
    actorId: input.result.provider,
    subjectUserId: input.candidate.requestedByUid,
    sourceType: "pinImage",
    targetType: "notePinImage",
    targetId: input.candidateId,
    targetPath: input.context.job.targetPath,
    placeId: input.target.placeId,
    jobId: input.context.jobId,
    candidateId: input.candidateId,
    accountSafetyRequired: input.result.action === "hidden",
    accountSafetyAppliedAt: input.result.action === "hidden" ?
      null : input.checkedAt,
    createdAt: input.checkedAt,
    expireAt: Timestamp.fromMillis(
      input.checkedAt.toMillis() +
        PIN_IMAGE_MODERATION_AUDIT_RETENTION_MILLIS,
    ),
    ...moderationAuditFields(input.result),
  };
}

function isPinImageModerationRejection(
  result: InternalModerationResult,
): result is PinImageModerationRejectionResult {
  return result.action !== "allow" && result.action !== "pending";
}

async function downloadPinImage(
  context: ModerationJobContext,
  candidate: PinImageCandidateData,
): Promise<Uint8Array> {
  const file = worldContext(context.job.world).bucket.file(
    candidate.storagePath,
  );
  try {
    const [[metadata], [bytes]] = await Promise.all([
      file.getMetadata(),
      file.download(),
    ]);
    if (metadata.contentType !== "image/webp" ||
        Number(metadata.size ?? bytes.length) > 256 * 1024) {
      const error = new Error("Pin image metadata is invalid.");
      Object.assign(error, {code: "moderation/invalid-image"});
      throw error;
    }
    return bytes;
  } catch (error) {
    if (typeof error === "object" && error !== null && "code" in error &&
        String((error as {code: unknown}).code).startsWith("moderation/")) {
      throw error;
    }
    const missing = new Error("Pin image upload was not found.");
    Object.assign(missing, {code: "moderation/image-missing"});
    throw missing;
  }
}

async function finalizePinImageModeration(
  context: ModerationJobContext,
  moderationResult: InternalModerationResult,
): Promise<PinImageModerationFinalization> {
  const target = pinImageModerationTarget(context.job.targetPath);
  const placeRef = context.firestore.doc(context.job.targetPath);
  const auditRef = context.firestore
    .collection("moderationAuditLogs")
    .doc(`pinImage_${context.jobId}`);

  return context.firestore.runTransaction(async (transaction) => {
    const place = await transaction.get(placeRef);
    if (!place.exists) {
      return {
        status: PIN_IMAGE_MODERATION_FINALIZATION_STATUS.superseded,
        reason: PIN_IMAGE_MODERATION_SUPERSEDED_REASON.targetMissing,
      };
    }
    let candidate: PinImageCandidateData;
    try {
      candidate = parsePinImageCandidate(
        place.get("pinImageCandidate"),
        target.placeId,
      );
    } catch {
      return {
        status: PIN_IMAGE_MODERATION_FINALIZATION_STATUS.superseded,
        reason: PIN_IMAGE_MODERATION_SUPERSEDED_REASON.candidateMissing,
      };
    }
    if (candidate.inputHash !== context.job.inputHash) {
      return {
        status: PIN_IMAGE_MODERATION_FINALIZATION_STATUS.superseded,
        reason: PIN_IMAGE_MODERATION_SUPERSEDED_REASON.candidateChanged,
      };
    }
    const checkedAt = Timestamp.now();
    const candidateId = pinImageCandidateId(candidate.storagePath);
    if (moderationResult.action === "allow") {
      const previousPath = place.get("pinImageStoragePath");
      if (typeof previousPath === "string" &&
          previousPath !== candidate.storagePath) {
        enqueueStorageObjectDeletion(transaction, context.firestore, {
          sourceOperationId: `replacedPin:${imageUploadId(previousPath)}`,
          revision: 1,
          world: context.job.world,
          objectPath: previousPath,
          createdAt: checkedAt,
        });
      }
      transaction.update(placeRef, {
        pinImageStoragePath: candidate.storagePath,
        pinImageCandidate: FieldValue.delete(),
        pinImageModerationAction: "allow",
        pinImageModerationProvider: moderationResult.provider,
        pinImageModerationPolicyVersion: moderationResult.policyVersion,
        pinImageModerationCheckedAt: checkedAt,
      });
      return {
        status: PIN_IMAGE_MODERATION_FINALIZATION_STATUS.accepted,
      };
    }
    if (!isPinImageModerationRejection(moderationResult)) {
      throw new Error("Pending pin image moderation cannot be finalized.");
    }

    enqueueStorageObjectDeletion(transaction, context.firestore, {
      sourceOperationId: `rejectedPin:${imageUploadId(candidate.storagePath)}`,
      revision: 1,
      world: context.job.world,
      objectPath: candidate.storagePath,
      createdAt: checkedAt,
    });
    transaction.update(placeRef, {
      pinImageCandidate: FieldValue.delete(),
    });
    transaction.create(auditRef, pinImageModerationAuditData({
      context,
      target,
      candidate,
      candidateId,
      result: moderationResult,
      checkedAt,
    }));
    return {
      status: PIN_IMAGE_MODERATION_FINALIZATION_STATUS.rejected,
      action: moderationResult.action,
    };
  });
}

async function applyPendingPinImageSafety(
  context: ModerationJobContext,
): Promise<boolean> {
  const auditRef = context.firestore
    .collection("moderationAuditLogs")
    .doc(`pinImage_${context.jobId}`);
  const audit = await auditRef.get();
  if (!audit.exists || audit.get("accountSafetyRequired") !== true) {
    return false;
  }
  if (audit.get("accountSafetyAppliedAt") instanceof Timestamp) return true;
  const uid = audit.get("subjectUserId");
  const candidateId = audit.get("candidateId");
  if (typeof uid !== "string" || typeof candidateId !== "string") {
    throw new Error("Pin image moderation audit is invalid.");
  }
  const home = await context.firestore.collection("userHomes").doc(uid).get();
  const homeWorld = home.get("world");
  if (!home.exists || typeof homeWorld !== "string") {
    const error = new Error("Pin image owner home assignment is missing.");
    Object.assign(error, {code: "moderation/home-missing"});
    throw error;
  }
  await executeAccountSafetyEvent({
    firestore: worldContext(homeWorld).firestore,
    authorityWorld: homeWorld,
    uid,
    operationId: derivedGlobalOperationId(
      candidateId,
      `hidden-pin-image-account-safety:${context.jobId}`,
    ),
    eventId: `pinImageModeration:${context.jobId}`,
    points: ACCOUNT_SAFETY_HIDDEN_CONTENT_POINTS,
    sourceWorld: context.job.world,
    sourceType: "pinImageModerationHidden",
    sourceEntityId: candidateId,
  });
  await context.firestore.runTransaction(async (transaction) => {
    const current = await transaction.get(auditRef);
    if (current.exists &&
        current.get("accountSafetyRequired") === true &&
        !(current.get("accountSafetyAppliedAt") instanceof Timestamp)) {
      transaction.update(auditRef, {
        accountSafetyAppliedAt: FieldValue.serverTimestamp(),
      });
    }
  });
  return true;
}

/** Evaluates one replaceable pin candidate without hiding its parent note. */
export const pinImageModerationJobHandler: ModerationJobHandler = {
  jobType: EVALUATE_PIN_IMAGE_MODERATION_JOB,
  async process(context): Promise<void> {
    if (await applyPendingPinImageSafety(context)) return;
    const target = pinImageModerationTarget(context.job.targetPath);
    const place = await context.firestore.doc(context.job.targetPath).get();
    if (!place.exists) return;
    let candidate: PinImageCandidateData;
    try {
      candidate = parsePinImageCandidate(
        place.get("pinImageCandidate"),
        target.placeId,
      );
    } catch {
      return;
    }
    if (candidate.inputHash !== context.job.inputHash) return;
    const bytes = await downloadPinImage(context, candidate);
    const result = await moderateContent("", [{
      bytes,
      contentType: "image/webp",
    }]);
    if (result.action === "pending") {
      const error = new Error(
        "Moderation provider is temporarily unavailable.",
      );
      Object.assign(error, {code: "moderation/provider-unavailable"});
      throw error;
    }
    const finalized = await finalizePinImageModeration(context, result);
    if (finalized.status ===
          PIN_IMAGE_MODERATION_FINALIZATION_STATUS.rejected &&
        finalized.action === "hidden") {
      await applyPendingPinImageSafety(context);
    }
  },
};
