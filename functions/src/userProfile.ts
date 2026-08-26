import {getAuth} from "firebase-admin/auth";
import {Firestore} from "firebase-admin/firestore";
import {onCall, HttpsError} from "./platform/worldCallable";

import {REGION} from "./constants";
import {
  executeGlobalCommand,
  GLOBAL_COMMAND_SCOPE,
  GlobalOperationBindingError,
  GlobalOperationValidationError,
} from "./globalOperations";
import {UPDATE_PUBLIC_PROFILE_OPERATION} from
  "./profileEntitlementReplication";

const MAX_DISPLAY_NAME_LENGTH = 20;
const LANGUAGE_PREFERENCES = new Set([
  "system",
  "en",
  "ja",
  "ko",
  "zh-Hans",
  "zh-Hant",
]);
/**
 * Returns the app profile fields shown in a note's member list.
 *
 * @param {Firestore} firestore The routed world's Firestore database.
 * @param {string} uid The signed-in user's uid.
 * @return {Promise<object>} User-facing profile fields.
 */
export async function profileForMember(
  firestore: Firestore,
  uid: string,
): Promise<{displayName: string; profileRevision: number}> {
  const snap = await firestore
    .collection("publicProfiles").doc(uid).get();
  if (!snap.exists) {
    throw new HttpsError("failed-precondition", "Public profile missing.");
  }
  const data = snap.data();
  const displayName = stringOrNull(data?.displayName);
  if (displayName === null) {
    throw new HttpsError("failed-precondition", "Public profile is invalid.");
  }
  const revision = data?.revision;
  if (typeof revision !== "number" ||
      !Number.isSafeInteger(revision) || revision <= 0) {
    throw new HttpsError("failed-precondition", "Profile revision is invalid.");
  }
  return {displayName, profileRevision: revision};
}

/**
 * Coerces non-empty strings to a display-safe value.
 *
 * @param {unknown} value The value to inspect.
 * @return {string | null} The trimmed string, or null.
 */
function stringOrNull(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/**
 * Updates the caller's nickname and refreshes access-list display names.
 */
export const updateDisplayName = onCall<{
  displayName?: unknown;
  operationId?: unknown;
}>(
  {
    auditAction: "profile.displayName.update",
    enforceAppCheck: true,
    region: REGION,
  },
  async (req, world) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const rawDisplayName = req.data?.displayName;
    if (typeof rawDisplayName !== "string") {
      throw new HttpsError("invalid-argument", "displayName is required.");
    }

    const displayName = rawDisplayName.trim();
    if (
      displayName.length === 0 ||
      displayName.length > MAX_DISPLAY_NAME_LENGTH
    ) {
      throw new HttpsError(
        "invalid-argument",
        `Nickname must be 1-${MAX_DISPLAY_NAME_LENGTH} characters.`,
      );
    }

    const userRef = world.firestore.collection("users").doc(uid);
    const homeRef = world.firestore.collection("userHomes").doc(uid);
    const publicProfileRef = world.firestore
      .collection("publicProfiles")
      .doc(uid);
    try {
      const operation = await executeGlobalCommand({
        firestore: world.firestore,
        authorityWorld: world.worldId,
        ownerUid: uid,
        operationId: req.data?.operationId,
        operationType: UPDATE_PUBLIC_PROFILE_OPERATION,
        entityId: uid,
        payload: {displayName},
        entityRef: publicProfileRef,
        scope: GLOBAL_COMMAND_SCOPE.allActiveWorlds,
        mutate: async ({transaction, entity, revision, acceptedAt}) => {
          const [home, user] = await Promise.all([
            transaction.get(homeRef),
            transaction.get(userRef),
          ]);
          if (!home.exists || home.get("world") !== world.worldId) {
            throw new HttpsError(
              "failed-precondition",
              "Profile updates must use the account's home world.",
            );
          }
          if (!user.exists || !entity.exists) {
            throw new HttpsError(
              "failed-precondition",
              "User profile missing.",
            );
          }
          transaction.update(userRef, {displayName, updatedAt: acceptedAt});
          transaction.update(publicProfileRef, {
            displayName,
            revision,
            updatedAt: acceptedAt,
          });
        },
      });

      // Firestore is authoritative. Auth remains a user-facing cache and is
      // also repaired by the authority global-operation trigger.
      await getAuth().updateUser(uid, {displayName});
      return {displayName, ...operation};
    } catch (error) {
      throw globalCommandHttpsError(error);
    }
  },
);

/**
 * Saves the caller's app-language preference on their private profile.
 * The device keeps a local mirror, but this account value is authoritative.
 */
export const setLanguagePreference = onCall<{
  languagePreference?: unknown;
  operationId?: unknown;
}>(
  {
    auditAction: "profile.language.update",
    enforceAppCheck: true,
    region: REGION,
  },
  async (req, world) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const languagePreference = req.data?.languagePreference;
    if (
      typeof languagePreference !== "string" ||
      !LANGUAGE_PREFERENCES.has(languagePreference)
    ) {
      throw new HttpsError(
        "invalid-argument",
        "Unsupported language preference.",
      );
    }

    const userRef = world.firestore.collection("users").doc(uid);
    const homeRef = world.firestore.collection("userHomes").doc(uid);
    try {
      const operation = await executeGlobalCommand({
        firestore: world.firestore,
        authorityWorld: world.worldId,
        ownerUid: uid,
        operationId: req.data?.operationId,
        operationType: "setLanguagePreference",
        entityId: uid,
        payload: {languagePreference},
        entityRef: userRef,
        revisionField: "languagePreferenceRevision",
        scope: GLOBAL_COMMAND_SCOPE.authorityOnly,
        mutate: async ({transaction, entity, revision, acceptedAt}) => {
          const home = await transaction.get(homeRef);
          if (!home.exists || home.get("world") !== world.worldId) {
            throw new HttpsError(
              "failed-precondition",
              "Account preferences must use the account's home world.",
            );
          }
          if (!entity.exists) {
            throw new HttpsError(
              "failed-precondition",
              "User profile missing.",
            );
          }
          transaction.update(userRef, {
            languagePreference,
            languagePreferenceRevision: revision,
            updatedAt: acceptedAt,
          });
        },
      });

      return {languagePreference, ...operation};
    } catch (error) {
      throw globalCommandHttpsError(error);
    }
  },
);

/**
 * Converts shared command validation into the stable callable contract.
 *
 * @param {unknown} error Command or domain error to translate.
 * @return {unknown} Stable callable error or the original domain error.
 */
function globalCommandHttpsError(error: unknown): unknown {
  if (error instanceof GlobalOperationBindingError) {
    return new HttpsError(
      "already-exists",
      "operationId is already bound to another command.",
    );
  }
  if (error instanceof GlobalOperationValidationError) {
    return new HttpsError("invalid-argument", error.message);
  }
  return error;
}
