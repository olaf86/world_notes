/* eslint-disable valid-jsdoc */

import {
  DocumentReference,
  DocumentSnapshot,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {
  GlobalReplicationApplyContext,
  GlobalReplicationHandler,
} from "./globalReplication";
import {
  executeGlobalCommand,
  GLOBAL_COMMAND_SCOPE,
  GlobalCommandResult,
} from "./globalOperations";
import {hasUserBlockBetweenInTransaction} from "./userBlocks";

export const SET_USER_FOLLOW_OPERATION = "setUserFollow";

const UID_PATTERN = /^[^/\s]{1,128}$/;
const EDGE_FIELDS = new Set([
  "followerUid",
  "followeeUid",
  "following",
  "revision",
  "createdAt",
  "updatedAt",
]);

export interface SocialEdgeProjection {
  readonly followerUid: string;
  readonly followeeUid: string;
  readonly following: boolean;
  readonly revision: number;
  readonly createdAt: Timestamp | null;
  readonly updatedAt: Timestamp;
}

export interface SocialCounterDeltas {
  readonly followerFollowingCount: number;
  readonly followeeFollowerCount: number;
}

export interface ApplySocialCounterTransitionInput {
  readonly transaction: Transaction;
  readonly followerProfileRef: DocumentReference;
  readonly followerProfile: DocumentSnapshot;
  readonly followeeProfileRef: DocumentReference;
  readonly followeeProfile: DocumentSnapshot;
  readonly previousFollowing: boolean;
  readonly nextFollowing: boolean;
}

export interface ExecuteSocialEdgeCommandInput {
  readonly firestore: Firestore;
  readonly authorityWorld: string;
  readonly followerUid: string;
  readonly followeeUid: string;
  readonly following: boolean;
  readonly operationId: unknown;
  readonly sourceEventId: string;
}

/** Replicates one follower-owned directed edge and its derived counts. */
export const socialEdgeReplicationHandler: GlobalReplicationHandler = {
  operationType: SET_USER_FOLLOW_OPERATION,
  apply: replicateSocialEdge,
};

/** Commits one follower-home edge transition and its global operation. */
export async function executeSocialEdgeCommand(
  input: ExecuteSocialEdgeCommandInput,
): Promise<GlobalCommandResult> {
  const edgeId = socialEdgeId(input.followerUid, input.followeeUid);
  const homeRef = input.firestore
    .collection("userHomes")
    .doc(input.followerUid);
  const followerProfileRef = input.firestore
    .collection("publicProfiles")
    .doc(input.followerUid);
  const followeeProfileRef = input.firestore
    .collection("publicProfiles")
    .doc(input.followeeUid);
  const edgeRef = input.firestore.collection("socialEdges").doc(edgeId);
  return executeGlobalCommand({
    firestore: input.firestore,
    authorityWorld: input.authorityWorld,
    ownerUid: input.followerUid,
    operationId: input.operationId,
    operationType: SET_USER_FOLLOW_OPERATION,
    entityId: edgeId,
    payload: {
      targetUserId: input.followeeUid,
      following: input.following,
      sourceEventId: input.sourceEventId,
    },
    entityRef: edgeRef,
    scope: GLOBAL_COMMAND_SCOPE.allActiveWorlds,
    mutate: async ({transaction, entity, revision, acceptedAt}) => {
      const isBlocked = await hasUserBlockBetweenInTransaction(
        transaction,
        input.firestore,
        input.followerUid,
        input.followeeUid,
      );
      const [home, followerProfile, followeeProfile] = await Promise.all([
        transaction.get(homeRef),
        transaction.get(followerProfileRef),
        transaction.get(followeeProfileRef),
      ]);
      if (!home.exists || home.get("world") !== input.authorityWorld) {
        throw new HttpsError(
          "failed-precondition",
          "Follow updates must use the follower's home world.",
        );
      }
      if (!followerProfile.exists) {
        throw new HttpsError(
          "failed-precondition",
          "Caller profile missing.",
        );
      }
      if (!followeeProfile.exists) {
        throw new HttpsError("not-found", "User not found.");
      }
      if (input.following && isBlocked) {
        throw new HttpsError(
          "failed-precondition",
          "You cannot follow a blocked user.",
          {reason: "user_blocked"},
        );
      }

      const previous = entity.exists ?
        parseSocialEdgeProjection(entity, edgeId) :
        undefined;
      applySocialCounterTransition({
        transaction,
        followerProfileRef,
        followerProfile,
        followeeProfileRef,
        followeeProfile,
        previousFollowing: previous?.following ?? false,
        nextFollowing: input.following,
      });
      transaction.set(edgeRef, {
        ...nextSocialEdgeProjection(
          input.followerUid,
          input.followeeUid,
          input.following,
          revision,
          acceptedAt,
          previous,
        ),
      });
    },
  });
}

/** Builds a delimiter-safe, globally stable directed-edge document ID. */
export function socialEdgeId(
  followerUid: string,
  followeeUid: string,
): string {
  requireUid(followerUid, "followerUid");
  requireUid(followeeUid, "followeeUid");
  if (followerUid === followeeUid) {
    throw new Error("A social edge cannot target its owner.");
  }
  return `${base64Url(followerUid)}.${base64Url(followeeUid)}`;
}

/** Parses one active edge or revisioned inactive tombstone. */
export function parseSocialEdgeProjection(
  snapshot: DocumentSnapshot,
  expectedEdgeId?: string,
): SocialEdgeProjection {
  if (!snapshot.exists) throw new Error("Social edge is missing.");
  const data = snapshot.data();
  if (data === undefined ||
      Object.keys(data).length !== EDGE_FIELDS.size ||
      [...EDGE_FIELDS].some((field) => !(field in data))) {
    throw new Error("Social edge fields are invalid.");
  }
  const followerUid = requireUid(data.followerUid, "followerUid");
  const followeeUid = requireUid(data.followeeUid, "followeeUid");
  const edgeId = socialEdgeId(followerUid, followeeUid);
  if (expectedEdgeId !== undefined && edgeId !== expectedEdgeId) {
    throw new Error("Social edge identity does not match its document path.");
  }
  if (typeof data.following !== "boolean") {
    throw new Error("Social edge following state is invalid.");
  }
  const createdAt = requireNullableTimestamp(data.createdAt, "createdAt");
  if (data.following && createdAt === null) {
    throw new Error("An active social edge requires createdAt.");
  }
  const updatedAt = requireTimestamp(data.updatedAt, "updatedAt");
  if (createdAt !== null && createdAt.toMillis() > updatedAt.toMillis()) {
    throw new Error("Social edge timestamps are invalid.");
  }
  return Object.freeze({
    followerUid,
    followeeUid,
    following: data.following,
    revision: requirePositiveInteger(data.revision, "revision"),
    createdAt,
    updatedAt,
  });
}

/** Builds the next authority projection without a legacy document shape. */
export function nextSocialEdgeProjection(
  followerUid: string,
  followeeUid: string,
  following: boolean,
  revision: number,
  acceptedAt: Timestamp,
  previous?: SocialEdgeProjection,
): SocialEdgeProjection {
  const edgeId = socialEdgeId(followerUid, followeeUid);
  if (previous !== undefined &&
      socialEdgeId(previous.followerUid, previous.followeeUid) !== edgeId) {
    throw new Error("Social edge authority identity cannot change.");
  }
  return Object.freeze({
    followerUid,
    followeeUid,
    following,
    revision: requirePositiveInteger(revision, "revision"),
    createdAt: following ?
      previous?.following === true ? previous.createdAt : acceptedAt :
      previous?.createdAt ?? null,
    updatedAt: acceptedAt,
  });
}

/** Returns the exact profile-counter delta for one edge state transition. */
export function socialCounterDeltas(
  previousFollowing: boolean,
  nextFollowing: boolean,
): SocialCounterDeltas {
  const delta = Number(nextFollowing) - Number(previousFollowing);
  return Object.freeze({
    followerFollowingCount: delta,
    followeeFollowerCount: delta,
  });
}

/** Applies derived profile counts in the same transaction as an edge. */
export function applySocialCounterTransition(
  input: ApplySocialCounterTransitionInput,
): void {
  const deltas = socialCounterDeltas(
    input.previousFollowing,
    input.nextFollowing,
  );
  const followingCount = requireProfileCounter(
    input.followerProfile,
    "followingCount",
  ) + deltas.followerFollowingCount;
  const followerCount = requireProfileCounter(
    input.followeeProfile,
    "followerCount",
  ) + deltas.followeeFollowerCount;
  if (followingCount < 0 || followerCount < 0) {
    throw new Error("Social profile counters would become negative.");
  }
  if (deltas.followerFollowingCount === 0) return;
  input.transaction.update(input.followerProfileRef, {followingCount});
  input.transaction.update(input.followeeProfileRef, {followerCount});
}

/** Copies the latest authority state with monotonic destination application. */
async function replicateSocialEdge(
  context: GlobalReplicationApplyContext,
): Promise<number> {
  if (context.operation.operationType !== SET_USER_FOLLOW_OPERATION) {
    throw new Error("Social replication received the wrong operation type.");
  }
  const sourceRef = context.authorityFirestore
    .collection("socialEdges")
    .doc(context.operation.entityId);
  const source = parseSocialEdgeProjection(
    await sourceRef.get(),
    context.operation.entityId,
  );
  if (source.followerUid !== context.operation.ownerUid) {
    throw new Error("Social edge operation owner is invalid.");
  }
  if (source.revision < context.operation.revision) {
    throw new Error("Social edge authority is behind its operation.");
  }

  const destinationEdgeRef = context.destinationFirestore
    .collection("socialEdges")
    .doc(context.operation.entityId);
  const followerProfileRef = context.destinationFirestore
    .collection("publicProfiles")
    .doc(source.followerUid);
  const followeeProfileRef = context.destinationFirestore
    .collection("publicProfiles")
    .doc(source.followeeUid);
  return context.destinationFirestore.runTransaction(async (transaction) => {
    const [destination, followerProfile, followeeProfile] = await Promise.all([
      transaction.get(destinationEdgeRef),
      transaction.get(followerProfileRef),
      transaction.get(followeeProfileRef),
    ]);
    const previous = destination.exists ?
      parseSocialEdgeProjection(destination, context.operation.entityId) :
      undefined;
    if (previous !== undefined && previous.revision >= source.revision) {
      return previous.revision;
    }
    applySocialCounterTransition({
      transaction,
      followerProfileRef,
      followerProfile,
      followeeProfileRef,
      followeeProfile,
      previousFollowing: previous?.following ?? false,
      nextFollowing: source.following,
    });
    transaction.set(destinationEdgeRef, {...source});
    return source.revision;
  });
}

/** Reads a required counter from one existing profile projection. */
function requireProfileCounter(
  snapshot: DocumentSnapshot,
  field: "followerCount" | "followingCount",
): number {
  if (!snapshot.exists) {
    throw new Error("Social counter profile projection is missing.");
  }
  const value = snapshot.get(field);
  if (typeof value !== "number" ||
      !Number.isSafeInteger(value) || value < 0) {
    throw new Error(`Social profile ${field} is invalid.`);
  }
  return value;
}

/** Encodes one UID without padding or delimiter ambiguity. */
function base64Url(value: string): string {
  return Buffer.from(value, "utf8").toString("base64url");
}

/** Validates a Firebase Auth UID used as a path segment. */
function requireUid(value: unknown, field: string): string {
  if (typeof value !== "string" || !UID_PATTERN.test(value)) {
    throw new Error(`Social edge ${field} is invalid.`);
  }
  return value;
}

/** Validates a positive safe integer. */
function requirePositiveInteger(value: unknown, field: string): number {
  if (typeof value !== "number" ||
      !Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`Social edge ${field} is invalid.`);
  }
  return value;
}

/** Validates a required Firestore timestamp. */
function requireTimestamp(value: unknown, field: string): Timestamp {
  if (!(value instanceof Timestamp)) {
    throw new Error(`Social edge ${field} is invalid.`);
  }
  return value;
}

/** Validates an explicitly nullable Firestore timestamp. */
function requireNullableTimestamp(
  value: unknown,
  field: string,
): Timestamp | null {
  if (value === null) return null;
  return requireTimestamp(value, field);
}
