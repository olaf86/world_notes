/* eslint-disable valid-jsdoc */

import {
  DocumentSnapshot,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";

import {
  executeGlobalCommand,
  GLOBAL_COMMAND_SCOPE,
  GlobalCommandResult,
  GlobalOperationData,
} from "./globalOperations";
import {
  GlobalReplicationApplyContext,
  GlobalReplicationHandler,
} from "./globalReplication";

export const UPDATE_PUBLIC_PROFILE_OPERATION = "updatePublicProfile";
export const SET_USER_ENTITLEMENT_OPERATION = "setUserEntitlement";

const MAX_DISPLAY_NAME_LENGTH = 20;
const MAX_PHOTO_URL_LENGTH = 2_000;
const UID_PATTERN = /^[^/\s]{1,128}$/;

export interface PublicProfileProjection {
  readonly displayName: string;
  readonly photoUrl: string | null;
  readonly photoVersion: number;
  readonly revision: number;
  readonly followerCount: number;
  readonly followingCount: number;
  readonly createdAt: Timestamp;
  readonly updatedAt: Timestamp;
}

export interface UserEntitlementProjection {
  readonly isPremium: boolean;
  readonly revision: number;
  readonly sourceCheckedAt: Timestamp | null;
  readonly updatedAt: Timestamp;
}

export interface ExecuteEntitlementUpdateInput {
  readonly firestore: Firestore;
  readonly authorityWorld: string;
  readonly uid: string;
  readonly operationId: unknown;
  readonly isPremium: boolean;
  readonly sourceCheckedAt: Timestamp | null;
  readonly sourceEventId: string;
}

export interface ExecutePublicProfilePublishInput {
  readonly firestore: Firestore;
  readonly authorityWorld: string;
  readonly uid: string;
  readonly operationId: unknown;
  readonly sourceEventId: string;
}

/** Replicates the public identity fields without clobbering social counters. */
export const publicProfileReplicationHandler: GlobalReplicationHandler = {
  operationType: UPDATE_PUBLIC_PROFILE_OPERATION,
  apply: replicatePublicProfile,
};

/** Replicates the complete server-only entitlement projection. */
export const userEntitlementReplicationHandler: GlobalReplicationHandler = {
  operationType: SET_USER_ENTITLEMENT_OPERATION,
  apply: replicateUserEntitlement,
};

/** Parses the trusted public-profile projection used by replication. */
export function parsePublicProfileProjection(
  snapshot: DocumentSnapshot,
): PublicProfileProjection {
  if (!snapshot.exists) throw new Error("Public profile authority is missing.");
  const displayName = requireTrimmedString(
    snapshot.get("displayName"),
    "displayName",
    MAX_DISPLAY_NAME_LENGTH,
  );
  const photoUrl = requireNullableTrimmedString(
    snapshot.get("photoUrl"),
    "photoUrl",
    MAX_PHOTO_URL_LENGTH,
  );
  return Object.freeze({
    displayName,
    photoUrl,
    photoVersion: requirePositiveInteger(
      snapshot.get("photoVersion"),
      "photoVersion",
    ),
    revision: requirePositiveInteger(snapshot.get("revision"), "revision"),
    followerCount: requireNonNegativeInteger(
      snapshot.get("followerCount"),
      "followerCount",
    ),
    followingCount: requireNonNegativeInteger(
      snapshot.get("followingCount"),
      "followingCount",
    ),
    createdAt: requireTimestamp(snapshot.get("createdAt"), "createdAt"),
    updatedAt: requireTimestamp(snapshot.get("updatedAt"), "updatedAt"),
  });
}

/** Parses the complete entitlement projection used by regional hot paths. */
export function parseUserEntitlementProjection(
  snapshot: DocumentSnapshot,
): UserEntitlementProjection {
  if (!snapshot.exists) {
    throw new Error("User entitlement authority is missing.");
  }
  const isPremium = snapshot.get("isPremium");
  if (typeof isPremium !== "boolean") {
    throw new Error("User entitlement isPremium is invalid.");
  }
  return Object.freeze({
    isPremium,
    revision: requirePositiveInteger(snapshot.get("revision"), "revision"),
    sourceCheckedAt: requireNullableTimestamp(
      snapshot.get("sourceCheckedAt"),
      "sourceCheckedAt",
    ),
    updatedAt: requireTimestamp(snapshot.get("updatedAt"), "updatedAt"),
  });
}

/** Publishes the current authority profile as one durable global operation. */
export async function executePublicProfilePublish(
  input: ExecutePublicProfilePublishInput,
): Promise<GlobalCommandResult> {
  requireUid(input.uid);
  requireTrimmedString(input.sourceEventId, "sourceEventId", 256);
  const profileRef = input.firestore
    .collection("publicProfiles")
    .doc(input.uid);
  return executeGlobalCommand({
    firestore: input.firestore,
    authorityWorld: input.authorityWorld,
    ownerUid: input.uid,
    operationId: input.operationId,
    operationType: UPDATE_PUBLIC_PROFILE_OPERATION,
    entityId: input.uid,
    payload: {sourceEventId: input.sourceEventId},
    entityRef: profileRef,
    scope: GLOBAL_COMMAND_SCOPE.allActiveWorlds,
    mutate: ({transaction, entity, revision, acceptedAt}) => {
      if (!entity.exists) {
        throw new Error("Public profile authority is missing.");
      }
      transaction.update(profileRef, {revision, updatedAt: acceptedAt});
    },
  });
}

/**
 * Applies one trusted subscription result at the user's home authority.
 *
 * The caller must obtain `isPremium` from RevenueCat or another trusted
 * subscription source. Client-supplied entitlement booleans must never reach
 * this boundary.
 */
export async function executeEntitlementUpdate(
  input: ExecuteEntitlementUpdateInput,
): Promise<GlobalCommandResult> {
  requireUid(input.uid);
  requireTrimmedString(input.sourceEventId, "sourceEventId", 256);
  const entitlementRef = input.firestore
    .collection("userEntitlements")
    .doc(input.uid);
  return executeGlobalCommand({
    firestore: input.firestore,
    authorityWorld: input.authorityWorld,
    ownerUid: input.uid,
    operationId: input.operationId,
    operationType: SET_USER_ENTITLEMENT_OPERATION,
    entityId: input.uid,
    // Provider observation time orders concurrent responses but does not alter
    // the command identity; a retry with the same state must remain replayable.
    payload: {
      isPremium: input.isPremium,
      sourceEventId: input.sourceEventId,
    },
    entityRef: entitlementRef,
    scope: GLOBAL_COMMAND_SCOPE.allActiveWorlds,
    mutate: ({transaction, entity, revision, acceptedAt}) => {
      if (!entity.exists) {
        throw new Error("User entitlement authority is missing.");
      }
      const currentCheckedAt = requireNullableTimestamp(
        entity.get("sourceCheckedAt"),
        "sourceCheckedAt",
      );
      const shouldApply = shouldApplyEntitlementSource(
        currentCheckedAt,
        input.sourceCheckedAt,
      );
      transaction.update(entitlementRef, {
        ...(shouldApply ? {
          isPremium: input.isPremium,
          sourceCheckedAt: input.sourceCheckedAt,
        } : {}),
        revision,
        updatedAt: acceptedAt,
      });
    },
  });
}

/** Prevents a slower old provider response from rolling entitlement back. */
export function shouldApplyEntitlementSource(
  current: Timestamp | null,
  candidate: Timestamp | null,
): boolean {
  if (candidate === null) return current === null;
  return current === null || candidate.toMillis() >= current.toMillis();
}

/**
 * Repairs the Firebase Auth display cache for a profile authority operation.
 */
export async function reconcilePublicProfileAuthCache(
  authorityFirestore: Firestore,
  authorityWorld: string,
  operation: GlobalOperationData,
): Promise<boolean> {
  if (operation.operationType !== UPDATE_PUBLIC_PROFILE_OPERATION) return false;
  if (operation.authorityWorld !== authorityWorld) {
    throw new Error("Public profile Auth cache authority is invalid.");
  }
  const uid = requireOperationOwner(operation);
  const [home, profileSnapshot] = await Promise.all([
    authorityFirestore.collection("userHomes").doc(uid).get(),
    authorityFirestore.collection("publicProfiles").doc(uid).get(),
  ]);
  if (!home.exists || home.get("world") !== authorityWorld) {
    throw new Error("Public profile home authority is invalid.");
  }
  const profile = parsePublicProfileProjection(profileSnapshot);
  if (profile.revision < operation.revision) {
    throw new Error("Public profile Auth cache source is stale.");
  }
  await getAuth().updateUser(uid, {
    displayName: profile.displayName,
    photoURL: profile.photoUrl,
  });
  return true;
}

/**
 * Copies the latest public profile into one destination with a revision guard.
 */
async function replicatePublicProfile(
  context: GlobalReplicationApplyContext,
): Promise<number> {
  const uid = requireOperationEntity(context, UPDATE_PUBLIC_PROFILE_OPERATION);
  const sourceRef = context.authorityFirestore
    .collection("publicProfiles")
    .doc(uid);
  const source = parsePublicProfileProjection(await sourceRef.get());
  requireSourceRevision(context, source.revision);
  const destinationRef = context.destinationFirestore
    .collection("publicProfiles")
    .doc(uid);

  return context.destinationFirestore.runTransaction(async (transaction) => {
    const destination = await transaction.get(destinationRef);
    const destinationRevision = projectionRevision(destination);
    if (destinationRevision >= source.revision) return destinationRevision;

    if (!destination.exists) {
      transaction.create(destinationRef, {...source});
    } else {
      transaction.set(
        destinationRef,
        {
          displayName: source.displayName,
          photoUrl: source.photoUrl,
          photoVersion: source.photoVersion,
          revision: source.revision,
          createdAt: source.createdAt,
          updatedAt: source.updatedAt,
        },
        {merge: true},
      );
    }
    return source.revision;
  });
}

/** Copies the latest entitlement into one destination with a revision guard. */
async function replicateUserEntitlement(
  context: GlobalReplicationApplyContext,
): Promise<number> {
  const uid = requireOperationEntity(context, SET_USER_ENTITLEMENT_OPERATION);
  const sourceRef = context.authorityFirestore
    .collection("userEntitlements")
    .doc(uid);
  const source = parseUserEntitlementProjection(await sourceRef.get());
  requireSourceRevision(context, source.revision);
  const destinationRef = context.destinationFirestore
    .collection("userEntitlements")
    .doc(uid);

  return context.destinationFirestore.runTransaction(async (transaction) => {
    const destination = await transaction.get(destinationRef);
    const destinationRevision = projectionRevision(destination);
    if (destinationRevision >= source.revision) return destinationRevision;
    transaction.set(destinationRef, {...source});
    return source.revision;
  });
}

/** Validates the operation binding before resolving an entity path. */
function requireOperationEntity(
  context: GlobalReplicationApplyContext,
  operationType: string,
): string {
  if (context.operation.operationType !== operationType) {
    throw new Error("Global replication handler received the wrong operation.");
  }
  requireUid(context.operation.entityId);
  if (context.operation.ownerUid !== context.operation.entityId) {
    throw new Error("User projection operation owner is invalid.");
  }
  return context.operation.entityId;
}

/** Validates a user-owned operation without a replication context. */
function requireOperationOwner(operation: GlobalOperationData): string {
  requireUid(operation.entityId);
  if (operation.ownerUid !== operation.entityId) {
    throw new Error("User projection operation owner is invalid.");
  }
  return operation.entityId;
}

/** Rejects an authority snapshot older than its durable operation. */
function requireSourceRevision(
  context: GlobalReplicationApplyContext,
  sourceRevision: number,
): void {
  if (sourceRevision < context.operation.revision) {
    throw new Error("Projection authority revision is behind its operation.");
  }
}

/** Reads the required revision of an existing destination projection. */
function projectionRevision(snapshot: DocumentSnapshot): number {
  if (!snapshot.exists) return 0;
  return requirePositiveInteger(snapshot.get("revision"), "revision");
}

/** Validates a user document path segment. */
function requireUid(value: unknown): string {
  if (typeof value !== "string" || !UID_PATTERN.test(value)) {
    throw new Error("User projection uid is invalid.");
  }
  return value;
}

/** Validates one non-empty normalized bounded string. */
function requireTrimmedString(
  value: unknown,
  field: string,
  maxLength: number,
): string {
  if (typeof value !== "string" || value.length === 0 ||
      value.length > maxLength || value.trim() !== value) {
    throw new Error(`User projection ${field} is invalid.`);
  }
  return value;
}

/** Validates one explicitly nullable normalized bounded string. */
function requireNullableTrimmedString(
  value: unknown,
  field: string,
  maxLength: number,
): string | null {
  if (value === null) return null;
  return requireTrimmedString(value, field, maxLength);
}

/** Validates a positive safe integer. */
function requirePositiveInteger(value: unknown, field: string): number {
  const integer = requireNonNegativeInteger(value, field);
  if (integer === 0) throw new Error(`User projection ${field} is invalid.`);
  return integer;
}

/** Validates a non-negative safe integer. */
function requireNonNegativeInteger(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw new Error(`User projection ${field} is invalid.`);
  }
  return value;
}

/** Validates a Firestore timestamp. */
function requireTimestamp(value: unknown, field: string): Timestamp {
  if (!(value instanceof Timestamp)) {
    throw new Error(`User projection ${field} is invalid.`);
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
