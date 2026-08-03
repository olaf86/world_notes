/* eslint-disable require-jsdoc, valid-jsdoc */

import {
  DocumentReference,
  DocumentSnapshot,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {
  cleanupJobId,
  cleanupJobPath,
  newCleanupJobData,
  NewCleanupJobInput,
} from "./cleanupJobs";
import {
  GlobalReplicationApplyContext,
  GlobalReplicationFinalizeContext,
  GlobalReplicationHandler,
} from "./globalReplication";
import {
  executeGlobalCommand,
  GLOBAL_COMMAND_SCOPE,
  GlobalCommandResult,
  requireOperationId,
} from "./globalOperations";

export const SET_USER_BLOCK_OPERATION = "setUserBlock";
export const BLOCK_RELATIONSHIP_CLEANUP_JOB = "cleanupBlockRelationship";
export const BLOCK_TOMBSTONE_RETENTION_MILLIS =
  90 * 24 * 60 * 60 * 1000;

const UID_PATTERN = /^[^/\s]{1,128}$/;
const BLOCK_FIELDS = new Set([
  "blockedUid",
  "isBlocked",
  "revision",
  "authorityWorld",
  "updatedAt",
  "expireAt",
]);

export interface UserBlockProjection {
  readonly blockedUid: string;
  readonly isBlocked: boolean;
  readonly revision: number;
  readonly authorityWorld: string;
  readonly updatedAt: Timestamp;
  readonly expireAt: Timestamp | null;
}

export interface ExecuteUserBlockCommandInput {
  readonly firestore: Firestore;
  readonly authorityWorld: string;
  readonly blockerUid: string;
  readonly blockedUid: string;
  readonly blocked: boolean;
  readonly operationId: unknown;
}

/** Replicates one blocker-owned directional enforcement edge. */
export const userBlockReplicationHandler: GlobalReplicationHandler = {
  operationType: SET_USER_BLOCK_OPERATION,
  apply: replicateUserBlock,
  finalize: finalizeUserBlock,
};

/** Returns one directed block document from a trusted pair. */
export function userBlockRef(
  firestore: Firestore,
  blockerUid: string,
  blockedUid: string,
): DocumentReference {
  requireUid(blockerUid, "blockerUid");
  requireUid(blockedUid, "blockedUid");
  return firestore
    .collection("users")
    .doc(blockerUid)
    .collection("blockedUsers")
    .doc(blockedUid);
}

/** Commits one blocker-home authority revision and its local cleanup intent. */
export async function executeUserBlockCommand(
  input: ExecuteUserBlockCommandInput,
): Promise<GlobalCommandResult> {
  const operationId = requireOperationId(input.operationId);
  requireUid(input.blockerUid, "blockerUid");
  requireUid(input.blockedUid, "blockedUid");
  if (input.blockerUid === input.blockedUid) {
    throw new HttpsError("invalid-argument", "You cannot block yourself.");
  }
  const blockRef = userBlockRef(
    input.firestore,
    input.blockerUid,
    input.blockedUid,
  );
  const homeRef = input.firestore
    .collection("userHomes")
    .doc(input.blockerUid);
  const targetProfileRef = input.firestore
    .collection("publicProfiles")
    .doc(input.blockedUid);
  const cleanup = blockCleanupJobInput({
    operationId,
    world: input.authorityWorld,
    blockerUid: input.blockerUid,
    blockedUid: input.blockedUid,
    revision: 1,
  });
  const cleanupRef = input.firestore.doc(
    cleanupJobPath("firestore", cleanupJobId(cleanup)),
  );

  return executeGlobalCommand({
    firestore: input.firestore,
    authorityWorld: input.authorityWorld,
    ownerUid: input.blockerUid,
    operationId,
    operationType: SET_USER_BLOCK_OPERATION,
    entityId: userBlockEntityId(input.blockerUid, input.blockedUid),
    payload: {blockedUid: input.blockedUid, blocked: input.blocked},
    entityRef: blockRef,
    scope: GLOBAL_COMMAND_SCOPE.allActiveWorlds,
    mutate: async ({transaction, revision, acceptedAt}) => {
      const [home, targetProfile] = await Promise.all([
        transaction.get(homeRef),
        transaction.get(targetProfileRef),
      ]);
      if (!home.exists || home.get("world") !== input.authorityWorld) {
        throw new HttpsError(
          "failed-precondition",
          "Block updates must use the blocker's home world.",
        );
      }
      if (!targetProfile.exists) {
        throw new HttpsError("not-found", "User not found.");
      }
      transaction.set(blockRef, {
        blockedUid: input.blockedUid,
        isBlocked: input.blocked,
        revision,
        authorityWorld: input.authorityWorld,
        updatedAt: acceptedAt,
        expireAt: null,
      });
      if (input.blocked) {
        const job = blockCleanupJobInput({
          operationId,
          world: input.authorityWorld,
          blockerUid: input.blockerUid,
          blockedUid: input.blockedUid,
          revision,
        });
        transaction.create(cleanupRef, {
          ...newCleanupJobData(job, acceptedAt),
        });
      }
    },
  });
}

/** Parses an authority edge or a 90-day inactive enforcement tombstone. */
export function parseUserBlockProjection(
  snapshot: DocumentSnapshot,
  blockerUid: string,
  expectedBlockedUid?: string,
): UserBlockProjection {
  if (!snapshot.exists) throw new Error("User block projection is missing.");
  const data = snapshot.data();
  if (data === undefined ||
      Object.keys(data).length !== BLOCK_FIELDS.size ||
      [...BLOCK_FIELDS].some((field) => !(field in data))) {
    throw new Error("User block projection fields are invalid.");
  }
  requireUid(blockerUid, "blockerUid");
  const blockedUid = requireUid(data.blockedUid, "blockedUid");
  if (expectedBlockedUid !== undefined && blockedUid !== expectedBlockedUid) {
    throw new Error("User block identity does not match its document path.");
  }
  if (typeof data.isBlocked !== "boolean") {
    throw new Error("User block state is invalid.");
  }
  const expireAt = requireNullableTimestamp(data.expireAt, "expireAt");
  if (data.isBlocked && expireAt !== null) {
    throw new Error("An active user block cannot expire.");
  }
  return Object.freeze({
    blockedUid,
    isBlocked: data.isBlocked,
    revision: requirePositiveInteger(data.revision, "revision"),
    authorityWorld: requireValue(data.authorityWorld, "authorityWorld"),
    updatedAt: requireTimestamp(data.updatedAt, "updatedAt"),
    expireAt,
  });
}

/** Encodes one directed pair as a reversible path-safe entity ID. */
export function userBlockEntityId(
  blockerUid: string,
  blockedUid: string,
): string {
  requireUid(blockerUid, "blockerUid");
  requireUid(blockedUid, "blockedUid");
  if (blockerUid === blockedUid) {
    throw new Error("A user block cannot target its owner.");
  }
  return `${base64Url(blockerUid)}.${base64Url(blockedUid)}`;
}

/** Decodes a trusted block entity ID stored on a cleanup job. */
export function parseUserBlockEntityId(
  entityId: string,
): Readonly<{blockerUid: string; blockedUid: string}> {
  const parts = entityId.split(".");
  if (parts.length !== 2) throw new Error("User block entity ID is invalid.");
  const blockerUid = decodeBase64Url(parts[0]);
  const blockedUid = decodeBase64Url(parts[1]);
  if (userBlockEntityId(blockerUid, blockedUid) !== entityId) {
    throw new Error("User block entity ID is not canonical.");
  }
  return Object.freeze({blockerUid, blockedUid});
}

/** Returns whether one existing directional document currently enforces. */
export function isActiveUserBlock(
  snapshot: DocumentSnapshot,
  blockerUid: string,
  blockedUid: string,
): boolean {
  return snapshot.exists &&
    parseUserBlockProjection(snapshot, blockerUid, blockedUid).isBlocked;
}

/** Copies the latest authority state and creates local cleanup atomically. */
async function replicateUserBlock(
  context: GlobalReplicationApplyContext,
): Promise<number> {
  const pair = parseUserBlockEntityId(context.operation.entityId);
  if (context.operation.ownerUid !== pair.blockerUid) {
    throw new Error("User block operation owner is invalid.");
  }
  const sourceRef = userBlockRef(
    context.authorityFirestore,
    pair.blockerUid,
    pair.blockedUid,
  );
  const source = parseUserBlockProjection(
    await sourceRef.get(),
    pair.blockerUid,
    pair.blockedUid,
  );
  if (source.revision < context.operation.revision ||
      source.authorityWorld !== context.operation.authorityWorld) {
    throw new Error("User block authority is behind its operation.");
  }

  const destinationRef = userBlockRef(
    context.destinationFirestore,
    pair.blockerUid,
    pair.blockedUid,
  );
  const job = blockCleanupJobInput({
    operationId: context.operation.operationId,
    world: context.destinationWorld,
    blockerUid: pair.blockerUid,
    blockedUid: pair.blockedUid,
    revision: source.revision,
  });
  const cleanupRef = context.destinationFirestore.doc(
    cleanupJobPath("firestore", cleanupJobId(job)),
  );
  return context.destinationFirestore.runTransaction(async (transaction) => {
    const [destination, cleanupSnapshot] = await Promise.all([
      transaction.get(destinationRef),
      transaction.get(cleanupRef),
    ]);
    const previousRevision = destination.exists ?
      parseUserBlockProjection(
        destination,
        pair.blockerUid,
        pair.blockedUid,
      ).revision :
      0;
    if (previousRevision >= source.revision) return previousRevision;

    transaction.set(destinationRef, {
      ...source,
      expireAt: null,
    });
    if (source.isBlocked && !cleanupSnapshot.exists) {
      transaction.create(cleanupRef, {
        ...newCleanupJobData(job, context.operation.acceptedAt),
      });
    }
    return source.revision;
  });
}

/** Starts destination tombstone retention only after all worlds acknowledge. */
async function finalizeUserBlock(
  context: GlobalReplicationFinalizeContext,
): Promise<void> {
  if (context.destinationWorld === context.operation.authorityWorld) return;
  const completedAt = context.operation.completedAt;
  if (!(completedAt instanceof Timestamp)) {
    throw new Error("Completed user block operation is missing completedAt.");
  }
  const pair = parseUserBlockEntityId(context.operation.entityId);
  const reference = userBlockRef(
    context.destinationFirestore,
    pair.blockerUid,
    pair.blockedUid,
  );
  await context.destinationFirestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) return;
    const projection = parseUserBlockProjection(
      snapshot,
      pair.blockerUid,
      pair.blockedUid,
    );
    if (projection.isBlocked ||
        projection.revision !== context.operation.revision) {
      return;
    }
    const expireAt = Timestamp.fromMillis(
      completedAt.toMillis() + BLOCK_TOMBSTONE_RETENTION_MILLIS,
    );
    if (projection.expireAt?.isEqual(expireAt) ?? false) return;
    transaction.update(reference, {expireAt});
  });
}

function blockCleanupJobInput(input: {
  readonly operationId: string;
  readonly world: string;
  readonly blockerUid: string;
  readonly blockedUid: string;
  readonly revision: number;
}): NewCleanupJobInput {
  return {
    sourceOperationId: input.operationId,
    entityType: "userBlock",
    entityId: userBlockEntityId(input.blockerUid, input.blockedUid),
    revision: input.revision,
    world: input.world,
    queue: "firestore",
    jobType: BLOCK_RELATIONSHIP_CLEANUP_JOB,
  };
}

function base64Url(value: string): string {
  return Buffer.from(value, "utf8").toString("base64url");
}

function decodeBase64Url(value: string): string {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new Error("User block entity ID encoding is invalid.");
  }
  return Buffer.from(value, "base64url").toString("utf8");
}

function requireUid(value: unknown, field: string): string {
  if (typeof value !== "string" || !UID_PATTERN.test(value)) {
    throw new Error(`User block ${field} is invalid.`);
  }
  return value;
}

function requireValue(value: unknown, field: string): string {
  if (typeof value !== "string" || !UID_PATTERN.test(value)) {
    throw new Error(`User block ${field} is invalid.`);
  }
  return value;
}

function requirePositiveInteger(value: unknown, field: string): number {
  if (typeof value !== "number" ||
      !Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`User block ${field} is invalid.`);
  }
  return value;
}

function requireTimestamp(value: unknown, field: string): Timestamp {
  if (!(value instanceof Timestamp)) {
    throw new Error(`User block ${field} is invalid.`);
  }
  return value;
}

function requireNullableTimestamp(
  value: unknown,
  field: string,
): Timestamp | null {
  if (value === null) return null;
  return requireTimestamp(value, field);
}
