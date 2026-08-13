/* eslint-disable require-jsdoc, valid-jsdoc */

import {createHash} from "node:crypto";

import {
  DocumentSnapshot,
  FieldPath,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

import {
  cleanupJobId,
  cleanupJobPath,
  CleanupJobHandler,
  newCleanupJobData,
  NewCleanupJobInput,
} from "./cleanupJobs";
import {
  HIDDEN_CONTENT_RETENTION_MILLIS,
  MODERATION_EVIDENCE_RETENTION_MILLIS,
} from "./moderationRetention";
import {enqueueStorageObjectDeletion} from "./storageObjectCleanup";

export const PURGE_HIDDEN_MESSAGE_JOB = "purgeHiddenMessage";

const MESSAGE_LIKE_PURGE_BATCH_SIZE = 50;
const PURGING_STAGE = "purgingMessageLikes" as const;
const TARGET_FIELDS = new Set([
  "targetPath",
  "placeId",
  "messageId",
  "world",
  "hiddenAt",
  "createdAt",
]);

interface HiddenMessageRetentionTarget {
  readonly targetPath: string;
  readonly placeId: string;
  readonly messageId: string;
  readonly world: string;
  readonly hiddenAt: Timestamp;
  readonly createdAt: Timestamp;
}

interface HiddenMessageRetentionCursor {
  readonly stage: typeof PURGING_STAGE;
  readonly pass: number;
}

/** Returns the sole post-purge evidence ID for one message identity. */
export function messageRetentionEvidenceId(
  placeId: string,
  messageId: string,
): string {
  if (placeId.length === 0 || messageId.length === 0) {
    throw new Error("Message retention evidence identity is invalid.");
  }
  const identity = createHash("sha256")
    .update(JSON.stringify([placeId, messageId]), "utf8")
    .digest("hex");
  return `messageRetention_${identity}`;
}

/** Creates one due-at-deadline cleanup intent beside a hidden message. */
export function enqueueHiddenMessageRetention(
  transaction: Transaction,
  firestore: Firestore,
  input: Readonly<{
    world: string;
    placeId: string;
    messageId: string;
    hiddenAt: Timestamp;
  }>,
): void {
  const targetPath = `places/${input.placeId}/messages/${input.messageId}`;
  const revision = input.hiddenAt.toMillis();
  const operationIdentity = createHash("sha256")
    .update(JSON.stringify([
      input.placeId,
      input.messageId,
      revision,
    ]), "utf8")
    .digest("hex");
  const jobInput: NewCleanupJobInput = {
    sourceOperationId: `hiddenMessage:${operationIdentity}`,
    entityType: "hiddenMessage",
    entityId: input.messageId,
    revision,
    world: input.world,
    queue: "firestore",
    jobType: PURGE_HIDDEN_MESSAGE_JOB,
    partition: input.placeId,
  };
  const jobId = cleanupJobId(jobInput);
  const purgeAt = Timestamp.fromMillis(
    revision + HIDDEN_CONTENT_RETENTION_MILLIS,
  );
  transaction.create(
    firestore.doc(cleanupJobPath("firestore", jobId)),
    {
      ...newCleanupJobData(jobInput, input.hiddenAt),
      nextAttemptAt: purgeAt,
    },
  );
  transaction.create(
    firestore.collection("moderationRetentionTargets").doc(jobId),
    {
      targetPath,
      placeId: input.placeId,
      messageId: input.messageId,
      world: input.world,
      hiddenAt: input.hiddenAt,
      createdAt: input.hiddenAt,
    },
  );
}

/** Permanently removes one still-hidden message after its appeal window. */
export const hiddenMessageRetentionHandler: CleanupJobHandler = {
  queue: "firestore",
  jobType: PURGE_HIDDEN_MESSAGE_JOB,
  async processBatch(context) {
    const targetRef = context.firestore
      .collection("moderationRetentionTargets")
      .doc(context.jobId);
    const targetSnapshot = await targetRef.get();
    if (!targetSnapshot.exists) return {complete: true};
    const target = parseRetentionTarget(targetSnapshot, context.job.world);
    requireTargetMatchesJob(target, context.job.entityId, context.job.revision);

    if (context.job.cursor === null) {
      const claimed = await claimHiddenMessagePurge(
        context.firestore,
        targetRef,
        target,
      );
      return claimed ?
        {complete: false, cursor: encodeCursor({
          stage: PURGING_STAGE,
          pass: 0,
        })} :
        {complete: true};
    }
    const cursor = parseCursor(context.job.cursor);
    const complete = await purgeHiddenMessageBatch(
      context.firestore,
      context.jobId,
      targetRef,
      target,
    );
    return complete ?
      {complete: true} :
      {complete: false, cursor: encodeCursor({
        stage: PURGING_STAGE,
        pass: cursor.pass + 1,
      })};
  },
};

async function claimHiddenMessagePurge(
  firestore: Firestore,
  targetRef: FirebaseFirestore.DocumentReference,
  target: HiddenMessageRetentionTarget,
): Promise<boolean> {
  return firestore.runTransaction(async (tx) => {
    const messageRef = firestore.doc(target.targetPath);
    const message = await tx.get(messageRef);
    if (!isCurrentHiddenMessage(message, target.hiddenAt)) {
      tx.delete(targetRef);
      return false;
    }
    if (!(message.get("moderationPurgeStartedAt") instanceof Timestamp)) {
      tx.update(messageRef, {
        moderationPurgeStartedAt: Timestamp.now(),
      });
    }
    return true;
  });
}

async function purgeHiddenMessageBatch(
  firestore: Firestore,
  jobId: string,
  targetRef: FirebaseFirestore.DocumentReference,
  target: HiddenMessageRetentionTarget,
): Promise<boolean> {
  return firestore.runTransaction(async (tx) => {
    const messageRef = firestore.doc(target.targetPath);
    const reviewRef = firestore
      .collection("moderationReviews")
      .doc(`${target.placeId}_${target.messageId}`);
    const likesQuery = messageRef.collection("messageLikes")
      .orderBy(FieldPath.documentId())
      .limit(MESSAGE_LIKE_PURGE_BATCH_SIZE);
    const [message, review, likes] = await Promise.all([
      tx.get(messageRef),
      tx.get(reviewRef),
      tx.get(likesQuery),
    ]);
    if (!message.exists) {
      tx.delete(targetRef);
      return true;
    }
    if (!isCurrentHiddenMessage(message, target.hiddenAt) ||
        !(message.get("moderationPurgeStartedAt") instanceof Timestamp)) {
      throw new Error("Hidden message changed after cleanup started.");
    }
    for (const like of likes.docs) tx.delete(like.ref);
    if (likes.size === MESSAGE_LIKE_PURGE_BATCH_SIZE) return false;

    const purgedAt = Timestamp.now();
    const imageStoragePaths = requireImageStoragePaths(
      message.get("imageStoragePaths"),
    );
    for (const objectPath of imageStoragePaths) {
      enqueueStorageObjectDeletion(tx, firestore, {
        sourceOperationId: `purgedHiddenMessage:${jobId}`,
        revision: 1,
        world: target.world,
        objectPath,
        createdAt: purgedAt,
      });
    }
    tx.set(
      firestore.collection("moderationAuditLogs")
        .doc(messageRetentionEvidenceId(target.placeId, target.messageId)),
      moderationEvidenceData({
        target,
        message,
        review,
        purgedAt,
      }),
    );
    if (review.exists) tx.delete(reviewRef);
    tx.delete(messageRef);
    tx.delete(targetRef);
    return true;
  });
}

function moderationEvidenceData(input: Readonly<{
  target: HiddenMessageRetentionTarget;
  message: DocumentSnapshot;
  review: DocumentSnapshot;
  purgedAt: Timestamp;
}>): Record<string, unknown> {
  return {
    worldId: input.target.world,
    eventType: "retentionPurge",
    actorType: "system",
    actorId: null,
    subjectUserId: input.message.get("userId") ?? null,
    targetType: "message",
    targetId: input.target.messageId,
    targetPath: input.target.targetPath,
    placeId: input.target.placeId,
    automatedAction: input.message.get("moderationAction") ?? null,
    moderationPolicyVersion:
      input.message.get("moderationPolicyVersion") ?? null,
    evaluatedAt: input.message.get("moderationCheckedAt") ?? null,
    administratorAction: input.review.get("humanDecision") ?? null,
    administratorUid: input.review.get("reviewedBy") ?? null,
    administratorReason: input.review.get("decisionReason") ?? null,
    decisionAt: input.review.get("reviewedAt") ?? null,
    hiddenAt: input.target.hiddenAt,
    purgedAt: input.purgedAt,
    createdAt: input.purgedAt,
    expireAt: Timestamp.fromMillis(
      input.purgedAt.toMillis() + MODERATION_EVIDENCE_RETENTION_MILLIS,
    ),
  };
}

function parseRetentionTarget(
  snapshot: DocumentSnapshot,
  expectedWorld: string,
): HiddenMessageRetentionTarget {
  const data = snapshot.data();
  if (data === undefined || Object.keys(data).length !== TARGET_FIELDS.size ||
      [...TARGET_FIELDS].some((field) => !(field in data)) ||
      typeof data.targetPath !== "string" ||
      typeof data.placeId !== "string" || data.placeId.length === 0 ||
      typeof data.messageId !== "string" || data.messageId.length === 0 ||
      data.world !== expectedWorld ||
      !(data.hiddenAt instanceof Timestamp) ||
      !(data.createdAt instanceof Timestamp) ||
      data.createdAt.toMillis() !== data.hiddenAt.toMillis() ||
      data.targetPath !==
        `places/${data.placeId}/messages/${data.messageId}`) {
    throw new Error("Hidden message retention target is invalid.");
  }
  return Object.freeze({
    targetPath: data.targetPath,
    placeId: data.placeId,
    messageId: data.messageId,
    world: data.world,
    hiddenAt: data.hiddenAt,
    createdAt: data.createdAt,
  });
}

function requireTargetMatchesJob(
  target: HiddenMessageRetentionTarget,
  entityId: string,
  revision: number,
): void {
  if (target.messageId !== entityId ||
      target.hiddenAt.toMillis() !== revision) {
    throw new Error("Hidden message retention job is invalid.");
  }
}

function isCurrentHiddenMessage(
  message: DocumentSnapshot,
  hiddenAt: Timestamp,
): boolean {
  const currentHiddenAt = message.get("deletedAt");
  return message.exists && message.get("moderationAction") === "hidden" &&
    message.get("isDeleted") === true &&
    message.get("deletedReason") === "moderation" &&
    currentHiddenAt instanceof Timestamp &&
    currentHiddenAt.toMillis() === hiddenAt.toMillis();
}

function requireImageStoragePaths(value: unknown): string[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) ||
      value.some((path) => typeof path !== "string" || path.length === 0)) {
    throw new Error("Hidden message image paths are invalid.");
  }
  return [...value] as string[];
}

function encodeCursor(cursor: HiddenMessageRetentionCursor): string {
  return JSON.stringify(cursor);
}

function parseCursor(value: string): HiddenMessageRetentionCursor {
  const parsed = JSON.parse(value) as unknown;
  if (typeof parsed !== "object" || parsed === null ||
      Array.isArray(parsed)) {
    throw new Error("Hidden message cleanup cursor is invalid.");
  }
  const cursor = parsed as Record<string, unknown>;
  if (cursor.stage !== PURGING_STAGE ||
      typeof cursor.pass !== "number" ||
      !Number.isSafeInteger(cursor.pass) || cursor.pass < 0) {
    throw new Error("Hidden message cleanup cursor is invalid.");
  }
  return cursor as unknown as HiddenMessageRetentionCursor;
}
