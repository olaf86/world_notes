/* eslint-disable valid-jsdoc */

import {getAuth, UserRecord} from "firebase-admin/auth";
import {
  DocumentSnapshot,
  FieldValue,
} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

import {
  newGlobalOperationId,
  requireOperationId,
} from "./globalOperations";
import {onCall, HttpsError} from "./platform/worldCallable";
import {asiaWorldContext} from "./platform/worldContext";
import {
  ASIA_WORLD_ID,
  WORLD_REGISTRY,
} from "./platform/worldRegistry";
import {
  executeEntitlementUpdate,
  executePublicProfilePublish,
} from "./profileEntitlementReplication";

const HOME_EPOCH = 1;
const MAX_DISPLAY_NAME_LENGTH = 20;
const MAX_EMAIL_LENGTH = 320;
const MAX_PHOTO_URL_LENGTH = 2000;
const PROFILE_REPLICATION_OPERATION_FIELD = "profileReplicationOperationId";
const ENTITLEMENT_REPLICATION_OPERATION_FIELD =
  "entitlementReplicationOperationId";
interface AssignHomeWorldData {
  readonly homeWorld?: unknown;
}

/**
 * Assigns the caller's immutable home and writes the Asia account bundle.
 *
 * The initial catalog deliberately enables only Asia as a new-account home.
 * Global replication will use the same directory document as its authority
 * and write this bundle in additional home-enabled worlds. Until then,
 * refusing a non-Asia assignment avoids presenting cross-database writes as
 * atomic.
 */
export const assignHomeWorld = onCall<AssignHomeWorldData>(
  {enforceAppCheck: true, requireAccountReady: false},
  async (request) => {
    const uid = request.auth?.uid;
    if (uid === undefined) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }

    const homeWorld = requireHomeWorld(request.data?.homeWorld);
    if (homeWorld !== ASIA_WORLD_ID) {
      throw new HttpsError(
        "failed-precondition",
        "This home world is not ready for account assignment.",
      );
    }

    const auth = getAuth();
    const authUser = await auth.getUser(uid);
    const db = asiaWorldContext().firestore;
    const homeRef = db.collection("userHomes").doc(uid);
    const userRef = db.collection("users").doc(uid);
    const profileRef = db.collection("publicProfiles").doc(uid);
    const entitlementRef = db.collection("userEntitlements").doc(uid);
    const usageRef = db.collection("userUsage").doc(uid);

    const candidateProfileOperationId = newGlobalOperationId();
    const candidateEntitlementOperationId = newGlobalOperationId();
    const bootstrap = await db.runTransaction(async (transaction) => {
      const [homeSnapshot, user, profile, entitlement, usage] =
        await Promise.all([
          transaction.get(homeRef),
          transaction.get(userRef),
          transaction.get(profileRef),
          transaction.get(entitlementRef),
          transaction.get(usageRef),
        ]);

      if (homeSnapshot.exists) {
        const existingWorld = homeSnapshot.get("world");
        const existingEpoch = homeSnapshot.get("epoch");
        if (existingWorld !== homeWorld || existingEpoch !== HOME_EPOCH) {
          throw new HttpsError(
            "already-exists",
            "This account already has a different home assignment.",
          );
        }
        requireCompleteAccountBundle(user, profile, entitlement, usage);
      } else {
        requireEmptyAccountBundle(user, profile, entitlement, usage);
        transaction.create(homeRef, {
          world: homeWorld,
          epoch: HOME_EPOCH,
          [PROFILE_REPLICATION_OPERATION_FIELD]:
            candidateProfileOperationId,
          [ENTITLEMENT_REPLICATION_OPERATION_FIELD]:
            candidateEntitlementOperationId,
          createdAt: FieldValue.serverTimestamp(),
        });
        transaction.create(userRef, privateUserData(authUser));
        transaction.create(profileRef, publicProfileData(authUser));
        transaction.create(entitlementRef, entitlementData());
        transaction.create(usageRef, usageData());
      }
      const assignedNow = !homeSnapshot.exists;
      const profileOperationId = assignedNow ?
        candidateProfileOperationId :
        operationIdFromHome(
          homeSnapshot,
          PROFILE_REPLICATION_OPERATION_FIELD,
        );
      const entitlementOperationId = assignedNow ?
        candidateEntitlementOperationId :
        operationIdFromHome(
          homeSnapshot,
          ENTITLEMENT_REPLICATION_OPERATION_FIELD,
        );
      const isPremium = assignedNow ? false : entitlement.get("isPremium");
      if (typeof isPremium !== "boolean") {
        throw new HttpsError(
          "failed-precondition",
          "User entitlement is invalid.",
        );
      }
      return {
        assignedNow,
        profileOperationId,
        entitlementOperationId,
        isPremium,
      };
    });

    await Promise.all([
      executePublicProfilePublish({
        firestore: db,
        authorityWorld: homeWorld,
        uid,
        operationId: bootstrap.profileOperationId,
        sourceEventId: "accountBootstrap:profile",
      }),
      executeEntitlementUpdate({
        firestore: db,
        authorityWorld: homeWorld,
        uid,
        operationId: bootstrap.entitlementOperationId,
        isPremium: bootstrap.isPremium,
        sourceCheckedAt: null,
        sourceEventId: "accountBootstrap:entitlement",
      }),
    ]);
    await cacheHomeClaim(authUser, homeWorld);
    return {
      homeWorld,
      epoch: HOME_EPOCH,
      ready: true,
      assignedNow: bootstrap.assignedNow,
    };
  },
);

/** Reads one required bootstrap operation ID from the home document. */
function operationIdFromHome(
  homeSnapshot: DocumentSnapshot,
  field: string,
): string {
  return requireOperationId(homeSnapshot.get(field));
}

/** Rejects a partially created authority bundle. */
function requireCompleteAccountBundle(
  ...snapshots: readonly DocumentSnapshot[]
): void {
  if (snapshots.some((snapshot) => !snapshot.exists)) {
    throw new HttpsError(
      "failed-precondition",
      "Account authority bundle is incomplete.",
    );
  }
}

/** Rejects orphaned account documents without an immutable home assignment. */
function requireEmptyAccountBundle(
  ...snapshots: readonly DocumentSnapshot[]
): void {
  if (snapshots.some((snapshot) => snapshot.exists)) {
    throw new HttpsError(
      "failed-precondition",
      "Account data exists without a home assignment.",
    );
  }
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
