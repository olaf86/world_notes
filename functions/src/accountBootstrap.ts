/* eslint-disable valid-jsdoc */

import {createHash} from "node:crypto";

import {getAuth, UserRecord} from "firebase-admin/auth";
import {
  DocumentSnapshot,
  FieldValue,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

import {
  newGlobalOperationId,
  requireOperationId,
} from "./globalOperations";
import {processGlobalOperation} from "./globalReplication";
import {productionGlobalReplicationRuntime} from "./globalReplicationRuntime";
import {onCall, HttpsError} from "./platform/worldCallable";
import {asiaWorldContext, worldContext} from "./platform/worldContext";
import {ASIA_WORLD_ID, WORLD_REGISTRY} from "./platform/worldRegistry";
import {
  executeEntitlementUpdate,
  executePublicProfilePublish,
} from "./profileEntitlementReplication";
import {
  executeAccountSafetyEvent,
  initialAccountSafetyData,
} from "./accountSafety";

const HOME_EPOCH = 1;
const MAX_DISPLAY_NAME_LENGTH = 20;
const MAX_EMAIL_LENGTH = 320;
const MAX_PHOTO_URL_LENGTH = 2000;
const HOME_RESERVATIONS_COLLECTION = "accountHomeReservations";
const PROFILE_REPLICATION_OPERATION_FIELD = "profileReplicationOperationId";
const ENTITLEMENT_REPLICATION_OPERATION_FIELD =
  "entitlementReplicationOperationId";
const SAFETY_REPLICATION_OPERATION_FIELD = "safetyReplicationOperationId";
interface AssignHomeWorldData {
  readonly homeWorld?: unknown;
}

interface HomeAssignmentData {
  readonly world: string;
  readonly epoch: number;
  readonly profileReplicationOperationId: string;
  readonly entitlementReplicationOperationId: string;
  readonly safetyReplicationOperationId: string;
  readonly createdAt: Timestamp;
}

interface ReservedHomeAssignment {
  readonly assignedNow: boolean;
  readonly home: HomeAssignmentData;
}

/**
 * Assigns the caller's immutable home and makes every world mirror ready.
 *
 * Asia remains the single assignment directory. A server-only reservation
 * serializes competing first requests before the selected home database is
 * initialized. Every step is idempotent so a retry can finish an interrupted
 * cross-database bootstrap without changing the chosen home.
 */
export const assignHomeWorld = onCall<AssignHomeWorldData>(
  {
    auditAction: "account.home.assign",
    enforceAppCheck: true,
    requireAccountReady: false,
    timeoutSeconds: 120,
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (uid === undefined) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }

    const homeWorld = requireHomeWorld(request.data?.homeWorld);
    const auth = getAuth();
    const authUser = await auth.getUser(uid);
    const directory = asiaWorldContext().firestore;
    const authority = worldContext(homeWorld).firestore;
    const reservation = await reserveHomeAssignment(
      directory,
      uid,
      homeWorld,
    );
    const bootstrap = await ensureAuthorityBundle(
      authority,
      uid,
      authUser,
      reservation.home,
    );

    await Promise.all([
      executePublicProfilePublish({
        firestore: authority,
        authorityWorld: homeWorld,
        uid,
        operationId: reservation.home.profileReplicationOperationId,
        sourceEventId: "accountBootstrap:profile",
      }),
      executeEntitlementUpdate({
        firestore: authority,
        authorityWorld: homeWorld,
        uid,
        operationId: reservation.home.entitlementReplicationOperationId,
        isPremium: bootstrap.isPremium,
        sourceCheckedAt: null,
        sourceEventId: "accountBootstrap:entitlement",
      }),
      executeAccountSafetyEvent({
        firestore: authority,
        authorityWorld: homeWorld,
        uid,
        operationId: reservation.home.safetyReplicationOperationId,
        eventId: bootstrapSafetyEventId(uid),
        points: 0,
        sourceWorld: homeWorld,
        sourceType: "accountBootstrap",
        sourceEntityId: uid,
      }),
    ]);
    await replicateBootstrapOperations(homeWorld, reservation.home);
    await publishHomeAssignment(uid, reservation.home);
    await clearHomeReservation(directory, uid, reservation.home);
    await cacheHomeClaim(authUser, homeWorld);
    return {
      homeWorld,
      epoch: HOME_EPOCH,
      ready: true,
      assignedNow: reservation.assignedNow,
    };
  },
);

/** Reserves one immutable choice in the Asia directory before remote writes. */
async function reserveHomeAssignment(
  directory: Firestore,
  uid: string,
  homeWorld: string,
): Promise<ReservedHomeAssignment> {
  const homeRef = directory.collection("userHomes").doc(uid);
  const reservationRef = directory
    .collection(HOME_RESERVATIONS_COLLECTION)
    .doc(uid);
  const candidate: HomeAssignmentData = Object.freeze({
    world: homeWorld,
    epoch: HOME_EPOCH,
    profileReplicationOperationId: newGlobalOperationId(),
    entitlementReplicationOperationId: newGlobalOperationId(),
    safetyReplicationOperationId: newGlobalOperationId(),
    createdAt: Timestamp.now(),
  });

  return directory.runTransaction(async (transaction) => {
    const [home, reservation] = await Promise.all([
      transaction.get(homeRef),
      transaction.get(reservationRef),
    ]);
    if (home.exists) {
      return {
        assignedNow: false,
        home: requireMatchingHomeAssignment(home, homeWorld),
      };
    }
    if (reservation.exists) {
      return {
        assignedNow: false,
        home: requireMatchingHomeAssignment(reservation, homeWorld),
      };
    }
    transaction.create(reservationRef, candidate);
    return {assignedNow: true, home: candidate};
  });
}

/** Creates or verifies the complete private bundle in the selected home. */
async function ensureAuthorityBundle(
  authority: Firestore,
  uid: string,
  authUser: UserRecord,
  home: HomeAssignmentData,
): Promise<{readonly isPremium: boolean}> {
  const homeRef = authority.collection("userHomes").doc(uid);
  const userRef = authority.collection("users").doc(uid);
  const profileRef = authority.collection("publicProfiles").doc(uid);
  const entitlementRef = authority.collection("userEntitlements").doc(uid);
  const usageRef = authority.collection("userUsage").doc(uid);
  const safetyRef = authority.collection("accountSafety").doc(uid);

  return authority.runTransaction(async (transaction) => {
    const [homeSnapshot, user, profile, entitlement, usage, safety] =
      await Promise.all([
        transaction.get(homeRef),
        transaction.get(userRef),
        transaction.get(profileRef),
        transaction.get(entitlementRef),
        transaction.get(usageRef),
        transaction.get(safetyRef),
      ]);
    if (homeSnapshot.exists) {
      requireMatchingHomeAssignment(homeSnapshot, home.world, home);
    }
    const bundle = [user, profile, entitlement, usage, safety];
    const existing = bundle.filter((snapshot) => snapshot.exists).length;
    if (existing !== 0 && existing !== bundle.length) {
      throw new HttpsError(
        "failed-precondition",
        "Account authority bundle is incomplete.",
      );
    }
    if (existing === bundle.length) {
      if (!homeSnapshot.exists) {
        throw new HttpsError(
          "failed-precondition",
          "Account data exists without a home assignment.",
        );
      }
      const isPremium = entitlement.get("isPremium");
      if (typeof isPremium !== "boolean") {
        throw new HttpsError(
          "failed-precondition",
          "User entitlement is invalid.",
        );
      }
      return {isPremium};
    }

    if (!homeSnapshot.exists) transaction.create(homeRef, home);
    transaction.create(userRef, privateUserData(authUser));
    transaction.create(profileRef, publicProfileData(authUser));
    transaction.create(entitlementRef, entitlementData());
    transaction.create(usageRef, usageData());
    transaction.create(
      safetyRef,
      initialAccountSafetyData(home.world, Timestamp.now()),
    );
    return {isPremium: false};
  });
}

/** Completes all initial projection operations before exposing readiness. */
async function replicateBootstrapOperations(
  homeWorld: string,
  home: HomeAssignmentData,
): Promise<void> {
  const operationIds = [
    home.profileReplicationOperationId,
    home.entitlementReplicationOperationId,
    home.safetyReplicationOperationId,
  ];
  const results = await Promise.all(operationIds.map((operationId) =>
    processGlobalOperation(
      homeWorld,
      operationId,
      productionGlobalReplicationRuntime,
    )));
  if (results.some((result) => result?.status !== "complete")) {
    throw new HttpsError(
      "unavailable",
      "Account mirrors are still being prepared.",
    );
  }
}

/** Publishes the immutable marker to every world, with Asia visible last. */
async function publishHomeAssignment(
  uid: string,
  home: HomeAssignmentData,
): Promise<void> {
  const worlds = [
    ...WORLD_REGISTRY.catalog.worlds.filter(
      (world) => world.worldId !== ASIA_WORLD_ID,
    ),
    WORLD_REGISTRY.requireWorld(ASIA_WORLD_ID),
  ];
  for (const world of worlds) {
    const firestore = worldContext(world.worldId).firestore;
    const homeRef = firestore.collection("userHomes").doc(uid);
    await firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(homeRef);
      if (snapshot.exists) {
        requireMatchingHomeAssignment(snapshot, home.world, home);
      } else {
        transaction.create(homeRef, home);
      }
    });
  }
}

/** Removes an obsolete reservation only after the public directory is ready. */
async function clearHomeReservation(
  directory: Firestore,
  uid: string,
  home: HomeAssignmentData,
): Promise<void> {
  const reservationRef = directory
    .collection(HOME_RESERVATIONS_COLLECTION)
    .doc(uid);
  await directory.runTransaction(async (transaction) => {
    const reservation = await transaction.get(reservationRef);
    if (!reservation.exists) return;
    requireMatchingHomeAssignment(reservation, home.world, home);
    transaction.delete(reservationRef);
  });
}

/** Parses and verifies a directory, reservation, or world-local marker. */
function requireMatchingHomeAssignment(
  snapshot: DocumentSnapshot,
  expectedWorld: string,
  expected?: HomeAssignmentData,
): HomeAssignmentData {
  const world = snapshot.get("world");
  const epoch = snapshot.get("epoch");
  if (world !== expectedWorld || epoch !== HOME_EPOCH) {
    throw new HttpsError(
      "already-exists",
      "This account already has a different home assignment.",
    );
  }
  let home: HomeAssignmentData;
  try {
    home = Object.freeze({
      world,
      epoch,
      profileReplicationOperationId: requireOperationId(
        snapshot.get(PROFILE_REPLICATION_OPERATION_FIELD),
      ),
      entitlementReplicationOperationId: requireOperationId(
        snapshot.get(ENTITLEMENT_REPLICATION_OPERATION_FIELD),
      ),
      safetyReplicationOperationId: requireOperationId(
        snapshot.get(SAFETY_REPLICATION_OPERATION_FIELD),
      ),
      createdAt: requireHomeTimestamp(snapshot.get("createdAt")),
    });
  } catch {
    throw new HttpsError(
      "failed-precondition",
      "Account home assignment is incomplete.",
    );
  }
  if (expected !== undefined && (
    home.profileReplicationOperationId !==
      expected.profileReplicationOperationId ||
    home.entitlementReplicationOperationId !==
      expected.entitlementReplicationOperationId ||
    home.safetyReplicationOperationId !==
      expected.safetyReplicationOperationId
  )) {
    throw new HttpsError(
      "failed-precondition",
      "Account home assignment operations do not match.",
    );
  }
  return home;
}

/** Requires one committed home timestamp. */
function requireHomeTimestamp(value: unknown): Timestamp {
  if (!(value instanceof Timestamp)) {
    throw new Error("Home assignment createdAt is invalid.");
  }
  return value;
}

/** Derives the one immutable safety-bootstrap receipt ID for an account. */
function bootstrapSafetyEventId(uid: string): string {
  return createHash("sha256")
    .update("accountSafetyBootstrap\0", "utf8")
    .update(uid, "utf8")
    .digest("hex");
}

/** Validates the requested home against the trusted activation catalog. */
function requireHomeWorld(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "homeWorld is required.");
  }
  try {
    return WORLD_REGISTRY.requireHomeWorld(value).worldId;
  } catch {
    throw new HttpsError(
      "failed-precondition",
      "The requested home world is not available.",
    );
  }
}

/** Builds the owner-only account document from trusted Auth identity. */
function privateUserData(authUser: UserRecord): Record<string, unknown> {
  return {
    displayName: displayNameOf(authUser),
    email: boundedNullableString(authUser.email, MAX_EMAIL_LENGTH),
    photoUrl: boundedNullableString(authUser.photoURL, MAX_PHOTO_URL_LENGTH),
    languagePreference: "system",
    languagePreferenceRevision: 0,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/** Builds the authenticated-readable public profile projection. */
function publicProfileData(authUser: UserRecord): Record<string, unknown> {
  const displayName = displayNameOf(authUser);
  const photoUrl = boundedNullableString(
    authUser.photoURL,
    MAX_PHOTO_URL_LENGTH,
  );

  return {
    displayName,
    photoUrl,
    photoVersion: 1,
    revision: 1,
    followerCount: 0,
    followingCount: 0,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/** Builds the initial server-owned entitlement projection. */
function entitlementData(): Record<string, unknown> {
  return {
    isPremium: false,
    revision: 1,
    sourceCheckedAt: null,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/** Builds the initial exact per-world note usage document. */
function usageData(): Record<string, unknown> {
  return {
    activeNoteCount: 0,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/** Keeps the caller's home in Auth as a cache, never as routing authority. */
async function cacheHomeClaim(
  authUser: UserRecord,
  homeWorld: string,
): Promise<void> {
  if (authUser.customClaims?.homeWorld === homeWorld &&
      authUser.customClaims?.homeEpoch === HOME_EPOCH) {
    return;
  }
  try {
    await getAuth().setCustomUserClaims(authUser.uid, {
      ...authUser.customClaims,
      homeWorld,
      homeEpoch: HOME_EPOCH,
    });
  } catch (error) {
    // Account readiness is the committed Firestore bundle. Claim refresh is a
    // cache optimization and is safely repairable on a later bootstrap call.
    logger.warn(`Could not cache home claim for ${authUser.uid}.`, error);
  }
}

/** Returns a bounded public display name from Firebase Auth. */
function displayNameOf(authUser: UserRecord): string {
  const value = authUser.displayName?.trim();
  if (value === undefined || value.length === 0) return "User";
  return Array.from(value).slice(0, MAX_DISPLAY_NAME_LENGTH).join("");
}

/** Normalizes one optional bounded Auth string. */
function boundedNullableString(
  value: string | undefined,
  maxLength: number,
): string | null {
  const normalized = value?.trim();
  if (normalized === undefined || normalized.length === 0) return null;
  return normalized.slice(0, maxLength);
}
