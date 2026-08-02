/* eslint-disable valid-jsdoc */

import {getAuth, UserRecord} from "firebase-admin/auth";
import {
  DocumentSnapshot,
  FieldValue,
  Timestamp,
} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

import {onCall, HttpsError} from "./platform/worldCallable";
import {asiaWorldContext} from "./platform/worldContext";
import {
  ASIA_WORLD_ID,
  WORLD_REGISTRY,
} from "./platform/worldRegistry";

const HOME_EPOCH = 1;
const MAX_DISPLAY_NAME_LENGTH = 20;
const MAX_EMAIL_LENGTH = 320;
const MAX_PHOTO_URL_LENGTH = 2000;
const LANGUAGE_PREFERENCES = new Set([
  "system",
  "en",
  "ja",
  "ko",
  "zh-Hans",
  "zh-Hant",
]);

interface AssignHomeWorldData {
  readonly homeWorld?: unknown;
}

/**
 * Assigns the caller's immutable home and installs the Asia account bundle.
 *
 * The initial catalog deliberately enables only Asia as a new-account home.
 * Global replication will use the same directory document as its authority
 * and install this bundle in additional home-enabled worlds. Until then,
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

    const assignedNow = await db.runTransaction(async (transaction) => {
      const [home, user, profile, entitlement, usage] = await Promise.all([
        transaction.get(homeRef),
        transaction.get(userRef),
        transaction.get(profileRef),
        transaction.get(entitlementRef),
        transaction.get(usageRef),
      ]);

      if (home.exists) {
        const existingWorld = home.get("world");
        const existingEpoch = home.get("epoch");
        if (existingWorld !== homeWorld || existingEpoch !== HOME_EPOCH) {
          throw new HttpsError(
            "already-exists",
            "This account already has a different home assignment.",
          );
        }
        if (user.exists &&
            profile.exists &&
            entitlement.exists &&
            usage.exists) {
          return false;
        }
      } else {
        transaction.create(homeRef, {
          world: homeWorld,
          epoch: HOME_EPOCH,
          createdAt: FieldValue.serverTimestamp(),
        });
      }

      transaction.set(userRef, privateUserData(authUser, user));
      transaction.set(profileRef, publicProfileData(authUser, profile));
      transaction.set(entitlementRef, entitlementData(user, entitlement));
      transaction.set(usageRef, usageData(user, usage));
      return !home.exists;
    });

    await cacheHomeClaim(authUser, homeWorld);
    return {
      homeWorld,
      epoch: HOME_EPOCH,
      ready: true,
      assignedNow,
    };
  },
);

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
function privateUserData(
  authUser: UserRecord,
  existing: DocumentSnapshot,
): Record<string, unknown> {
  const data: Record<string, unknown> = {
    displayName: displayNameOf(authUser),
    email: boundedNullableString(authUser.email, MAX_EMAIL_LENGTH),
    photoUrl: boundedNullableString(authUser.photoURL, MAX_PHOTO_URL_LENGTH),
    languagePreference: languagePreferenceOf(existing),
    languagePreferenceRevision: nonNegativeInteger(
      existing.get("languagePreferenceRevision"),
      0,
    ),
    createdAt: timestampOrServer(existing.get("createdAt")),
    updatedAt: FieldValue.serverTimestamp(),
  };

  // These fields remain private account state until P15 moves moderation
  // authority into accountSafety/{uid}. Copy only the known schema so an old
  // client cannot preserve arbitrary or privileged fields during bootstrap.
  copyKnownFields(existing, data, [
    "moderationStatus",
    "violationPoints",
    "lastViolationAt",
    "restrictedUntil",
    "bannedUntil",
    "locale",
  ]);
  return data;
}

/** Builds the authenticated-readable public profile projection. */
function publicProfileData(
  authUser: UserRecord,
  existing: DocumentSnapshot,
): Record<string, unknown> {
  const displayName = displayNameOf(authUser);
  const photoUrl = boundedNullableString(
    authUser.photoURL,
    MAX_PHOTO_URL_LENGTH,
  );
  const oldPhotoUrl = nullableString(existing.get("photoUrl"));
  const oldPhotoVersion = nonNegativeInteger(existing.get("photoVersion"), 0);
  const photoVersion = existing.exists && oldPhotoUrl === photoUrl ?
    Math.max(1, oldPhotoVersion) :
    Math.max(1, oldPhotoVersion + 1);

  return {
    displayName,
    photoUrl,
    photoVersion,
    followerCount: nonNegativeInteger(existing.get("followerCount"), 0),
    followingCount: nonNegativeInteger(existing.get("followingCount"), 0),
    createdAt: timestampOrServer(existing.get("createdAt")),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/** Migrates the current entitlement bit out of the private user document. */
function entitlementData(
  oldUser: DocumentSnapshot,
  existing: DocumentSnapshot,
): Record<string, unknown> {
  const current = existing.get("isPremium");
  const legacy = oldUser.get("isPremium");
  return {
    isPremium: typeof current === "boolean" ? current : legacy === true,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/** Migrates the per-world active-note counter into its local document. */
function usageData(
  oldUser: DocumentSnapshot,
  existing: DocumentSnapshot,
): Record<string, unknown> {
  const current = existing.get("activeNoteCount");
  const legacy = oldUser.get("activeNoteCount");
  return {
    activeNoteCount: nonNegativeInteger(current, nonNegativeInteger(legacy, 0)),
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

/** Preserves a supported private language preference. */
function languagePreferenceOf(existing: DocumentSnapshot): string {
  const value = existing.get("languagePreference");
  return typeof value === "string" && LANGUAGE_PREFERENCES.has(value) ?
    value :
    "system";
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

/** Reads a nullable string from existing projection data. */
function nullableString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

/** Reads a non-negative integer or returns the supplied fallback. */
function nonNegativeInteger(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 ?
    value :
    fallback;
}

/** Preserves a creation timestamp or allocates one at commit time. */
function timestampOrServer(value: unknown): Timestamp | FieldValue {
  return value instanceof Timestamp ? value : FieldValue.serverTimestamp();
}

/** Copies only explicitly allowlisted transitional private fields. */
function copyKnownFields(
  source: DocumentSnapshot,
  destination: Record<string, unknown>,
  fields: readonly string[],
): void {
  for (const field of fields) {
    const value = source.get(field);
    if (value !== undefined) destination[field] = value;
  }
}
