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
  "hiddenAt",
  "createdAt",
]);
const NOTE_PURGE_STAGE = Object.freeze({
  messages: "purgingMessages",
  likes: "purgingLikes",
  visitors: "purgingVisitors",
  members: "purgingMembers",
  attempts: "purgingAttempts",
  administrators: "purgingAdministrators",
  administratorAudits: "purgingAdministratorAudits",
  counters: "purgingCounters",
  secret: "purgingSecret",
  reports: "purgingReports",
  reviews: "purgingModerationReviews",
  invitations: "purgingAdministratorInvitations",
  place: "purgingPlace",
} as const);

type NotePurgeStage = typeof NOTE_PURGE_STAGE[keyof typeof NOTE_PURGE_STAGE];

const NOTE_PURGE_STAGES: readonly NotePurgeStage[] = [
  NOTE_PURGE_STAGE.messages,
  NOTE_PURGE_STAGE.likes,
  NOTE_PURGE_STAGE.visitors,
  NOTE_PURGE_STAGE.members,
  NOTE_PURGE_STAGE.attempts,
  NOTE_PURGE_STAGE.administrators,
  NOTE_PURGE_STAGE.administratorAudits,
  NOTE_PURGE_STAGE.counters,
  NOTE_PURGE_STAGE.secret,
  NOTE_PURGE_STAGE.reports,
  NOTE_PURGE_STAGE.reviews,
  NOTE_PURGE_STAGE.invitations,
  NOTE_PURGE_STAGE.place,
];

const NOTE_SUBCOLLECTION_BY_STAGE = new Map<NotePurgeStage, string>([
  [NOTE_PURGE_STAGE.likes, "likes"],
  [NOTE_PURGE_STAGE.visitors, "visitors"],
  [NOTE_PURGE_STAGE.members, "members"],
  [NOTE_PURGE_STAGE.attempts, "attempts"],
  [NOTE_PURGE_STAGE.administrators, "administrators"],
  [NOTE_PURGE_STAGE.administratorAudits, "administratorAudits"],
  [NOTE_PURGE_STAGE.counters, "counters"],
  [NOTE_PURGE_STAGE.secret, "secret"],
]);

interface HiddenNoteRetentionTarget {
  readonly targetPath: string;
  readonly placeId: string;
  readonly world: string;
  readonly hiddenAt: Timestamp;
  readonly createdAt: Timestamp;
}

interface HiddenNoteRetentionCursor {
  readonly stage: NotePurgeStage;
  readonly pass: number;
}

/** Returns the sole post-purge evidence ID for one note identity. */
export function noteRetentionAuditId(placeId: string): string {
  if (placeId.length === 0) {
    throw new Error("Note retention audit identity is invalid.");
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
    hiddenAt: Timestamp;
  }>,
): void {
  const targetPath = `places/${input.placeId}`;
  const revision = input.hiddenAt.toMillis();
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
      ...newCleanupJobData(jobInput, input.hiddenAt),
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
      hiddenAt: input.hiddenAt,
      createdAt: input.hiddenAt,
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
      return claimed ? incompleteCursor(NOTE_PURGE_STAGE.messages, 0) :
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
    if (!isCurrentHiddenNote(place, target.hiddenAt)) {
      tx.delete(targetRef);
      return false;
    }
    if (!(place.get("moderationPurgeStartedAt") instanceof Timestamp)) {
      tx.update(placeRef, {moderationPurgeStartedAt: Timestamp.now()});
    }
    return true;
  });
}

async function processPurgeStage(
  context: CleanupBatchContext,
  targetRef: FirebaseFirestore.DocumentReference,
  target: HiddenNoteRetentionTarget,
  stage: NotePurgeStage,
): Promise<boolean> {
  if (stage === NOTE_PURGE_STAGE.messages) {
    return purgeMessageBatch(context, target);
  }
  const subcollection = NOTE_SUBCOLLECTION_BY_STAGE.get(stage);
  if (subcollection !== undefined) {
    return purgeSubcollectionBatch(context.firestore, target, subcollection);
  }
  if (stage === NOTE_PURGE_STAGE.reports) {
    return purgeTopLevelBatch(context.firestore, target, "reports");
  }
  if (stage === NOTE_PURGE_STAGE.reviews) {
    return purgeTopLevelBatch(
      context.firestore,
      target,
      "moderationReviews",
    );
  }
  if (stage === NOTE_PURGE_STAGE.invitations) {
    return purgeTopLevelBatch(
      context.firestore,
      target,
      "noteAdministratorInvitations",
    );
  }
  if (stage === NOTE_PURGE_STAGE.place) {
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
    requirePurgeBarrier(place, target.hiddenAt);
    if (messages.empty) return true;

    const message = messages.docs[0];
    const likes = await tx.get(message.ref.collection("messageLikes")
      .orderBy(FieldPath.documentId())
      .limit(DELETE_BATCH_SIZE));
    if (!likes.empty) {
      for (const like of likes.docs) tx.delete(like.ref);
      return false;
    }

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
    requirePurgeBarrier(place, target.hiddenAt);
    for (const document of documents.docs) tx.delete(document.ref);
    return documents.empty;
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
    requirePurgeBarrier(place, target.hiddenAt);
    for (const document of documents.docs) tx.delete(document.ref);
    return documents.empty;
  });
}

async function purgePlace(
  context: CleanupBatchContext,
  targetRef: FirebaseFirestore.DocumentReference,
  target: HiddenNoteRetentionTarget,
): Promise<void> {
  const placeRef = context.firestore.doc(target.targetPath);
  await context.firestore.runTransaction(async (tx) => {
    const place = await tx.get(placeRef);
    requirePurgeBarrier(place, target.hiddenAt);
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
        .doc(noteRetentionAuditId(target.placeId)),
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
    hiddenAt: target.hiddenAt,
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
      !(data.hiddenAt instanceof Timestamp) ||
      !(data.createdAt instanceof Timestamp) ||
      data.createdAt.toMillis() !== data.hiddenAt.toMillis() ||
      data.targetPath !== `places/${data.placeId}`) {
    throw new Error("Hidden note retention target is invalid.");
  }
  return Object.freeze({
    targetPath: data.targetPath,
    placeId: data.placeId,
    world: data.world,
    hiddenAt: data.hiddenAt,
    createdAt: data.createdAt,
  });
}

function requireTargetMatchesJob(
  target: HiddenNoteRetentionTarget,
  entityId: string,
  revision: number,
): void {
  if (target.placeId !== entityId ||
      target.hiddenAt.toMillis() !== revision) {
    throw new Error("Hidden note retention job is invalid.");
  }
}

function isCurrentHiddenNote(
  place: DocumentSnapshot,
  hiddenAt: Timestamp,
): boolean {
  const currentHiddenAt = place.get("moderationHiddenAt");
  return place.exists && place.get("moderationAction") === "hidden" &&
    place.get("isModerationHidden") === true &&
    currentHiddenAt instanceof Timestamp &&
    currentHiddenAt.toMillis() === hiddenAt.toMillis();
}

function requirePurgeBarrier(
  place: DocumentSnapshot,
  hiddenAt: Timestamp,
): void {
  if (!isCurrentHiddenNote(place, hiddenAt) ||
      !(place.get("moderationPurgeStartedAt") instanceof Timestamp)) {
    throw new Error("Hidden note changed after cleanup started.");
  }
}

function stageAfter(stage: NotePurgeStage): NotePurgeStage | null {
  const index = NOTE_PURGE_STAGES.indexOf(stage);
  if (index < 0) throw new Error("Hidden note purge stage is invalid.");
  return NOTE_PURGE_STAGES[index + 1] ?? null;
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
      !NOTE_PURGE_STAGES.includes(cursor.stage as NotePurgeStage) ||
      typeof cursor.pass !== "number" ||
      !Number.isSafeInteger(cursor.pass) || cursor.pass < 0) {
    throw new Error("Hidden note cleanup cursor is invalid.");
  }
  return Object.freeze({
    stage: cursor.stage as NotePurgeStage,
    pass: cursor.pass,
  });
}
