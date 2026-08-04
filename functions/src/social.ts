import {onCall, HttpsError} from "./platform/worldCallable";
import * as logger from "firebase-functions/logger";

import {REGION} from "./constants";
import {
  GlobalOperationBindingError,
  GlobalOperationValidationError,
} from "./globalOperations";
import {createUserNotice} from "./notices";
import {
  executeSocialEdgeCommand,
  parseSocialEdgeProjection,
  socialEdgeId,
} from "./socialEdgeReplication";
import {hasUserBlockBetween} from "./userBlocks";
import {executeUserBlockCommand} from "./userBlockReplication";

interface SetUserFollowData {
  targetUserId?: unknown;
  following?: unknown;
  operationId?: unknown;
}

interface SetUserBlockData {
  targetUserId?: unknown;
  blocked?: unknown;
  operationId?: unknown;
}

const MAX_UID_LENGTH = 128;

/**
 * Validates a user id supplied by a client callable.
 *
 * @param {unknown} value The raw value.
 * @return {string} A trimmed uid.
 */
function assertUserId(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "targetUserId is required.");
  }
  const uid = value.trim();
  if (uid.length === 0 || uid.length > MAX_UID_LENGTH || uid.includes("/")) {
    throw new HttpsError("invalid-argument", "Invalid targetUserId.");
  }
  return uid;
}

/**
 * Validates the desired follow state.
 *
 * @param {unknown} value The raw value.
 * @return {boolean} The desired follow state.
 */
function assertFollowing(value: unknown): boolean {
  if (typeof value !== "boolean") {
    throw new HttpsError("invalid-argument", "following must be a boolean.");
  }
  return value;
}

/**
 * Validates the desired block state.
 *
 * @param {unknown} value The raw value.
 * @return {boolean} The desired block state.
 */
function assertBlocked(value: unknown): boolean {
  if (typeof value !== "boolean") {
    throw new HttpsError("invalid-argument", "blocked must be a boolean.");
  }
  return value;
}

/**
 * Sets the caller's final follow state for a target user.
 */
export const setUserFollow = onCall<SetUserFollowData>(
  {enforceAppCheck: true, region: REGION},
  async (req, world) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const targetUserId = assertUserId(req.data?.targetUserId);
    const desiredFollowing = assertFollowing(req.data?.following);
    if (targetUserId === uid) {
      throw new HttpsError("invalid-argument", "You cannot follow yourself.");
    }

    const db = world.firestore;
    const followerProfileRef = db.collection("publicProfiles").doc(uid);
    const edgeRef = db
      .collection("socialEdges")
      .doc(socialEdgeId(uid, targetUserId));

    let operation;
    try {
      operation = await executeSocialEdgeCommand({
        firestore: db,
        authorityWorld: world.worldId,
        followerUid: uid,
        followeeUid: targetUserId,
        following: desiredFollowing,
        operationId: req.data?.operationId,
        sourceEventId: "clientSetUserFollow",
      });
    } catch (error) {
      throw socialCommandHttpsError(error);
    }

    if (desiredFollowing && !operation.replayed) {
      try {
        const [edgeSnapshot, followerProfile] = await Promise.all([
          edgeRef.get(),
          followerProfileRef.get(),
        ]);
        const edge = parseSocialEdgeProjection(edgeSnapshot, edgeRef.id);
        const createdFollow = edge.following &&
          edge.revision === operation.revision &&
          edge.createdAt?.toMillis() === edge.updatedAt.toMillis();
        // Notice creation is outside the follow transaction. A block may have
        // committed after that transaction and removed the new follow edge.
        if (createdFollow &&
            !await hasUserBlockBetween(db, uid, targetUserId)) {
          const followerName = followerProfile.get("displayName");
          if (typeof followerName !== "string" || followerName.length === 0) {
            throw new Error("Follower public profile is invalid.");
          }
          await createUserNotice(db, targetUserId, {
            category: "social",
            severity: "info",
            title: "New follower",
            body: `${followerName} followed you.`,
            sourceType: "userFollow",
            sourceId: uid,
            push: true,
          });
        }
      } catch (error) {
        logger.error("setUserFollow: failed to create follower notice.", {
          followerUid: uid,
          followeeUid: targetUserId,
          error,
        });
      }
    }

    return {following: desiredFollowing, ...operation};
  },
);

/**
 * Converts global-command validation into the stable callable contract.
 *
 * @param {unknown} error Command or domain error.
 * @return {unknown} Stable callable error or original domain error.
 */
function socialCommandHttpsError(error: unknown): unknown {
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

/**
 * Sets the caller's final block state for another user.
 *
 * The authority transaction applies enforcement and a durable local cleanup
 * intent. Follow, note-access, scheduled-message, and Storage cleanup then
 * converges independently without delaying the callable response.
 */
export const setUserBlock = onCall<SetUserBlockData>(
  {enforceAppCheck: true, region: REGION},
  async (req, world) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const targetUserId = assertUserId(req.data?.targetUserId);
    const desiredBlocked = assertBlocked(req.data?.blocked);
    if (targetUserId === uid) {
      throw new HttpsError("invalid-argument", "You cannot block yourself.");
    }

    try {
      const operation = await executeUserBlockCommand({
        firestore: world.firestore,
        authorityWorld: world.worldId,
        blockerUid: uid,
        blockedUid: targetUserId,
        blocked: desiredBlocked,
        operationId: req.data?.operationId,
      });
      return {blocked: desiredBlocked, ...operation};
    } catch (error) {
      throw socialCommandHttpsError(error);
    }
  },
);
