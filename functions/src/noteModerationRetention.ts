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
  type CleanupBatchContext,
  type CleanupJobHandler,
  newCleanupJobData,
  type NewCleanupJobInput,
} from "./cleanupJobs";
import {parseImageStorageRoute} from "./imageAccess";
import {
  HIDDEN_CONTENT_RETENTION_MILLIS,
  MODERATION_EVIDENCE_RETENTION_MILLIS,
} from "./moderationRetention";
import {parsePinImageCandidate} from "./pinImageCandidate";
import {enqueueStorageObjectDeletion} from "./storageObjectCleanup";

export const PURGE_HIDDEN_NOTE_JOB = "purgeHiddenNote";

const DELETE_BATCH_SIZE = 50;
const NOTE_RETENTION_TARGET_FIELDS = new Set([
  "targetPath",
  "placeId",
  "world",
  "retentionStartedAt",
  "createdAt",
]);
type NotePurgeStepDefinition =
  | Readonly<{stage: string; kind: "messages"}>
  | Readonly<{stage: string; kind: "subcollection"; collection: string}>
  | Readonly<{stage: string; kind: "topLevel"; collection: string}>
  | Readonly<{stage: string; kind: "place"}>;

// This is the single ownership catalog for note-scoped Firestore data.
// Specialized message cleanup runs first because it also owns Storage files.
const NOTE_PURGE_PLAN = [
  {stage: "purgingMessages", kind: "messages"},
  {stage: "purgingLikes", kind: "subcollection", collection: "likes"},
  {
    stage: "purgingLikedMessages",
    kind: "subcollection",
    collection: "likedMessages",
  },
  {
    stage: "purgingVisitors",
    kind: "subcollection",
    collection: "visitors",
  },
  {stage: "purgingMembers", kind: "subcollection", collection: "members"},
  {
    stage: "purgingAttempts",
    kind: "subcollection",
    collection: "attempts",
  },
  {
    stage: "purgingAdministrators",
    kind: "subcollection",
    collection: "administrators",
  },
  {
    stage: "purgingAdministratorAudits",
    kind: "subcollection",
    collection: "administratorAudits",
  },
  {
    stage: "purgingCounters",
    kind: "subcollection",
    collection: "counters",
  },
  {stage: "purgingSecret", kind: "subcollection", collection: "secret"},
  {stage: "purgingReports", kind: "topLevel", collection: "reports"},
  {
    stage: "purgingModerationReviews",
    kind: "topLevel",
    collection: "moderationReviews",
  },
  {
    stage: "purgingAdministratorInvitations",
    kind: "topLevel",
    collection: "noteAdministratorInvitations",
  },
  {stage: "purgingPlace", kind: "place"},
] as const satisfies readonly NotePurgeStepDefinition[];

type NotePurgeStep = typeof NOTE_PURGE_PLAN[number];
type NotePurgeStage = NotePurgeStep["stage"];

const NOTE_PURGE_STEP_BY_STAGE = new Map(
  NOTE_PURGE_PLAN.map((step) => [step.stage, step] as const),
);
if (NOTE_PURGE_STEP_BY_STAGE.size !== NOTE_PURGE_PLAN.length) {
  throw new Error("Hidden note purge stages must be unique.");
}

interface HiddenNoteRetentionTarget {
  readonly targetPath: string;
  readonly placeId: string;
  readonly world: string;
  readonly retentionStartedAt: Timestamp;
  readonly createdAt: Timestamp;
}

interface HiddenNoteRetentionCursor {
  readonly stage: NotePurgeStage;
  readonly pass: number;
}

/** Returns the sole post-purge evidence ID for one note identity. */
export function noteRetentionEvidenceId(placeId: string): string {
  if (placeId.length === 0) {
    throw new Error("Note retention evidence identity is invalid.");
  }
  const identity = createHash("sha256")
    .update(JSON.stringify([placeId]), "utf8")
    .digest("hex");
  return `noteRetention_${identity}`;
}

/** Creates one cleanup intent due 30 days after a note becomes hidden. */
export function enqueueHiddenNoteRetention(
  transaction: Transaction,
  firestore: Firestore,
  input: Readonly<{
    world: string;
    placeId: string;
    retentionStartedAt: Timestamp;
  }>,
): void {
  const targetPath = `places/${input.placeId}`;
  const revision = input.retentionStartedAt.toMillis();
  const operationIdentity = createHash("sha256")
    .update(JSON.stringify([input.placeId, revision]), "utf8")
    .digest("hex");
  const jobInput: NewCleanupJobInput = {
    sourceOperationId: `hiddenNote:${operationIdentity}`,
    entityType: "hiddenNote",
    entityId: input.placeId,
    revision,
    world: input.world,
    queue: "firestore",
    jobType: PURGE_HIDDEN_NOTE_JOB,
    partition: input.placeId,
  };
  const jobId = cleanupJobId(jobInput);
  transaction.create(
    firestore.doc(cleanupJobPath("firestore", jobId)),
    {
      ...newCleanupJobData(jobInput, input.retentionStartedAt),
      nextAttemptAt: Timestamp.fromMillis(
        revision + HIDDEN_CONTENT_RETENTION_MILLIS,
      ),
    },
  );
  transaction.create(
    firestore.collection("noteModerationRetentionTargets").doc(jobId),
    {
      targetPath,
      placeId: input.placeId,
      world: input.world,
      retentionStartedAt: input.retentionStartedAt,
      createdAt: input.retentionStartedAt,
    },
  );
}

/** Permanently removes one still-hidden note and its known content tree. */
export const hiddenNoteRetentionHandler: CleanupJobHandler = {
  queue: "firestore",
  jobType: PURGE_HIDDEN_NOTE_JOB,
  async processBatch(context) {
    const targetRef = context.firestore
      .collection("noteModerationRetentionTargets")
      .doc(context.jobId);
    const snapshot = await targetRef.get();
    if (!snapshot.exists) return {complete: true};
    const target = parseRetentionTarget(snapshot, context.job.world);
    requireTargetMatchesJob(target, context.job.entityId, context.job.revision);

    if (context.job.cursor === null) {
      const claimed = await claimHiddenNotePurge(
        context.firestore,
        targetRef,
        target,
      );
      return claimed ? incompleteCursor(NOTE_PURGE_PLAN[0].stage, 0) :
        {complete: true};
    }

    const cursor = parseCursor(context.job.cursor);
    const stageComplete = await processPurgeStage(
      context,
      targetRef,
      target,
      cursor.stage,
    );
    if (!stageComplete) {
      return incompleteCursor(cursor.stage, cursor.pass + 1);
    }
    const nextStage = stageAfter(cursor.stage);
    return nextStage === null ? {complete: true} :
      incompleteCursor(nextStage, cursor.pass + 1);
  },
};

async function claimHiddenNotePurge(
  firestore: Firestore,
  targetRef: FirebaseFirestore.DocumentReference,
  target: HiddenNoteRetentionTarget,
): Promise<boolean> {
  return firestore.runTransaction(async (tx) => {
    const placeRef = firestore.doc(target.targetPath);
    const place = await tx.get(placeRef);
    if (!isCurrentHiddenNote(place, target.retentionStartedAt)) {
      tx.delete(targetRef);
      return false;
    }
    if (!(place.get("moderationRetentionPurgeStartedAt") instanceof
        Timestamp)) {
      tx.update(placeRef, {
        moderationRetentionPurgeStartedAt: Timestamp.now(),
      });
    }
    return true;
  });
}

async function processPurgeStage(
  context: CleanupBatchContext,
  targetRef: FirebaseFirestore.DocumentReference,
  target: HiddenNoteRetentionTarget,
  stageName: NotePurgeStage,
): Promise<boolean> {
  const step = NOTE_PURGE_STEP_BY_STAGE.get(stageName);
  if (step === undefined) {
    throw new Error("Hidden note purge stage is unsupported.");
  }
  if (step.kind === "messages") {
    return purgeMessageBatch(context, target);
  }
  if (step.kind === "subcollection") {
    return purgeSubcollectionBatch(
      context.firestore,
      target,
      step.collection,
    );
  }
  if (step.kind === "topLevel") {
    return purgeTopLevelBatch(
      context.firestore,
      target,
      step.collection,
    );
  }
  if (step.kind === "place") {
    await purgePlace(context, targetRef, target);
    return true;
  }
  throw new Error("Hidden note purge stage is unsupported.");
}

async function purgeMessageBatch(
  context: CleanupBatchContext,
  target: HiddenNoteRetentionTarget,
): Promise<boolean> {
  const placeRef = context.firestore.doc(target.targetPath);
  const messagesQuery = placeRef.collection("messages")
    .orderBy(FieldPath.documentId())
    .limit(1);
  return context.firestore.runTransaction(async (tx) => {
    const [place, messages] = await Promise.all([
      tx.get(placeRef),
      tx.get(messagesQuery),
    ]);
    requirePurgeBarrier(place, target.retentionStartedAt);
    if (messages.empty) return true;

    const message = messages.docs[0];
    const purgedAt = Timestamp.now();
    for (const objectPath of requireMessageImagePaths(
      message.get("imageStoragePaths"),
    )) {
      enqueueStorageObjectDeletion(tx, context.firestore, {
        sourceOperationId: context.job.sourceOperationId,
        revision: context.job.revision,
        world: target.world,
        objectPath,
        createdAt: purgedAt,
      });
    }
    tx.delete(context.firestore.collection("moderationReviews")
      .doc(`${target.placeId}_${message.id}`));
    tx.delete(message.ref);
    return false;
  });
}

async function purgeSubcollectionBatch(
  firestore: Firestore,
  target: HiddenNoteRetentionTarget,
  subcollection: string,
): Promise<boolean> {
  const placeRef = firestore.doc(target.targetPath);
  const query = placeRef.collection(subcollection)
    .orderBy(FieldPath.documentId())
    .limit(DELETE_BATCH_SIZE);
  return firestore.runTransaction(async (tx) => {
    const [place, documents] = await Promise.all([
      tx.get(placeRef),
      tx.get(query),
    ]);
    requirePurgeBarrier(place, target.retentionStartedAt);
    for (const document of documents.docs) tx.delete(document.ref);
    return documents.size < DELETE_BATCH_SIZE;
  });
}

async function purgeTopLevelBatch(
  firestore: Firestore,
  target: HiddenNoteRetentionTarget,
  collection: string,
): Promise<boolean> {
  const placeRef = firestore.doc(target.targetPath);
  const query = firestore.collection(collection)
    .where("placeId", "==", target.placeId)
    .limit(DELETE_BATCH_SIZE);
  return firestore.runTransaction(async (tx) => {
    const [place, documents] = await Promise.all([
      tx.get(placeRef),
      tx.get(query),
    ]);
    requirePurgeBarrier(place, target.retentionStartedAt);
    for (const document of documents.docs) tx.delete(document.ref);
    return documents.size < DELETE_BATCH_SIZE;
  });
}

async function purgePlace(
  context: CleanupBatchContext,
  targetRef: FirebaseFirestore.DocumentReference,
  target: HiddenNoteRetentionTarget,
): Promise<void> {
  const placeRef = context.firestore.doc(target.targetPath);
  const remainingSubcollections = await placeRef.listCollections();
  if (remainingSubcollections.length !== 0) {
    throw new Error(
      "Hidden note has unregistered or incompletely purged subcollections: " +
      remainingSubcollections.map((collection) => collection.id).join(","),
    );
  }
  await context.firestore.runTransaction(async (tx) => {
    const place = await tx.get(placeRef);
    requirePurgeBarrier(place, target.retentionStartedAt);
    const purgedAt = Timestamp.now();
    for (const objectPath of noteImagePaths(place, target.placeId)) {
      enqueueStorageObjectDeletion(tx, context.firestore, {
        sourceOperationId: context.job.sourceOperationId,
        revision: context.job.revision,
        world: target.world,
        objectPath,
        createdAt: purgedAt,
      });
    }
    tx.set(
      context.firestore.collection("moderationAuditLogs")
        .doc(noteRetentionEvidenceId(target.placeId)),
      noteModerationEvidenceData(target, place, purgedAt),
    );
    tx.delete(placeRef);
    tx.delete(targetRef);
  });
}

function noteModerationEvidenceData(
  target: HiddenNoteRetentionTarget,
  place: DocumentSnapshot,
  purgedAt: Timestamp,
): Record<string, unknown> {
  const reviewedAt = place.get("moderationReviewedAt");
  return {
    worldId: target.world,
    eventType: "retentionPurge",
    actorType: "system",
    actorId: null,
    subjectUserId: place.get("createdByUserId") ?? null,
    targetType: "note",
    targetId: target.placeId,
    targetPath: target.targetPath,
    placeId: target.placeId,
    automatedAction: place.get("moderationAction") ?? null,
    moderationPolicyVersion: place.get("moderationPolicyVersion") ?? null,
    evaluatedAt: place.get("moderationCheckedAt") ?? null,
    administratorAction: reviewedAt instanceof Timestamp ?
      place.get("moderationAction") ?? null : null,
    administratorUid: place.get("moderationReviewedBy") ?? null,
    administratorReason: place.get("moderationReviewReason") ?? null,
    decisionAt: reviewedAt ?? null,
    hiddenAt: target.retentionStartedAt,
    purgedAt,
    createdAt: purgedAt,
    expireAt: Timestamp.fromMillis(
      purgedAt.toMillis() + MODERATION_EVIDENCE_RETENTION_MILLIS,
    ),
  };
}

function noteImagePaths(
  place: DocumentSnapshot,
  placeId: string,
): readonly string[] {
  const paths = new Set<string>();
  const acceptedPath = place.get("pinImageStoragePath");
  if (acceptedPath !== undefined && acceptedPath !== null) {
    if (typeof acceptedPath !== "string") {
      throw new Error("Hidden note pin image path is invalid.");
    }
    const route = parseImageStorageRoute(acceptedPath);
    if (route.kind !== "pin" || route.placeId !== placeId) {
      throw new Error("Hidden note pin image route is invalid.");
    }
    paths.add(acceptedPath);
  }
  const candidateValue = place.get("pinImageCandidate");
  if (candidateValue !== undefined && candidateValue !== null) {
    paths.add(parsePinImageCandidate(candidateValue, placeId).storagePath);
  }
  return [...paths];
}

function requireMessageImagePaths(value: unknown): readonly string[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) ||
      value.some((path) => typeof path !== "string" || path.length === 0)) {
    throw new Error("Hidden note message image paths are invalid.");
  }
  return [...value] as string[];
}

function parseRetentionTarget(
  snapshot: DocumentSnapshot,
  expectedWorld: string,
): HiddenNoteRetentionTarget {
  const data = snapshot.data();
  if (data === undefined ||
      Object.keys(data).length !== NOTE_RETENTION_TARGET_FIELDS.size ||
      [...NOTE_RETENTION_TARGET_FIELDS].some((field) => !(field in data)) ||
      typeof data.targetPath !== "string" ||
      typeof data.placeId !== "string" || data.placeId.length === 0 ||
      data.world !== expectedWorld ||
      !(data.retentionStartedAt instanceof Timestamp) ||
      !(data.createdAt instanceof Timestamp) ||
      data.createdAt.toMillis() !== data.retentionStartedAt.toMillis() ||
      data.targetPath !== `places/${data.placeId}`) {
    throw new Error("Hidden note retention target is invalid.");
  }
  return Object.freeze({
    targetPath: data.targetPath,
    placeId: data.placeId,
    world: data.world,
    retentionStartedAt: data.retentionStartedAt,
    createdAt: data.createdAt,
  });
}

function requireTargetMatchesJob(
  target: HiddenNoteRetentionTarget,
  entityId: string,
  revision: number,
): void {
  if (target.placeId !== entityId ||
      target.retentionStartedAt.toMillis() !== revision) {
    throw new Error("Hidden note retention job is invalid.");
  }
}

function isCurrentHiddenNote(
  place: DocumentSnapshot,
  retentionStartedAt: Timestamp,
): boolean {
  const currentRetentionStartedAt = place.get(
    "moderationRetentionStartedAt",
  );
  return place.exists && place.get("moderationAction") === "hidden" &&
    place.get("isModerationHidden") === true &&
    currentRetentionStartedAt instanceof Timestamp &&
    currentRetentionStartedAt.toMillis() === retentionStartedAt.toMillis();
}

function requirePurgeBarrier(
  place: DocumentSnapshot,
  retentionStartedAt: Timestamp,
): void {
  if (!isCurrentHiddenNote(place, retentionStartedAt) ||
      !(place.get("moderationRetentionPurgeStartedAt") instanceof Timestamp)) {
    throw new Error("Hidden note changed after cleanup started.");
  }
}

function stageAfter(stage: NotePurgeStage): NotePurgeStage | null {
  const index = NOTE_PURGE_PLAN.findIndex((step) => step.stage === stage);
  if (index < 0) throw new Error("Hidden note purge stage is invalid.");
  return NOTE_PURGE_PLAN[index + 1]?.stage ?? null;
}

function incompleteCursor(stage: NotePurgeStage, pass: number) {
  return {
    complete: false as const,
    cursor: JSON.stringify({stage, pass}),
  };
}

function parseCursor(value: string): HiddenNoteRetentionCursor {
  const parsed = JSON.parse(value) as unknown;
  if (typeof parsed !== "object" || parsed === null ||
      Array.isArray(parsed)) {
    throw new Error("Hidden note cleanup cursor is invalid.");
  }
  const cursor = parsed as Record<string, unknown>;
  if (Object.keys(cursor).length !== 2 ||
      !NOTE_PURGE_STEP_BY_STAGE.has(cursor.stage as NotePurgeStage) ||
      typeof cursor.pass !== "number" ||
      !Number.isSafeInteger(cursor.pass) || cursor.pass < 0) {
    throw new Error("Hidden note cleanup cursor is invalid.");
  }
  return Object.freeze({
    stage: cursor.stage as NotePurgeStage,
    pass: cursor.pass,
  });
}
