import {onCall, HttpsError} from "./platform/worldCallable";
import * as logger from "firebase-functions/logger";
import {
  DocumentReference,
  DocumentSnapshot,
  FieldPath,
  FieldValue,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

import {MAX_MESSAGES_PER_THREAD, REGION} from "./constants";
import {
  GlobalOperationBindingError,
  GlobalOperationValidationError,
} from "./globalOperations";
import {asiaWorldContext} from "./platform/worldContext";
import {createUserNotice} from "./notices";
import {
  executeSocialEdgeCommand,
  nextSocialEdgeProjection,
  parseSocialEdgeProjection,
  socialEdgeId,
} from "./socialEdgeReplication";
import {
  hasUserBlockBetween,
  userBlockRef,
} from "./userBlocks";

interface SetUserFollowData {
  targetUserId?: unknown;
  following?: unknown;
  operationId?: unknown;
}

interface SetUserBlockData {
  targetUserId?: unknown;
  blocked?: unknown;
}

interface PublicProfileData {
  displayName: string;
  photoUrl: string | null;
  photoVersion: number;
}

const MAX_UID_LENGTH = 128;
const UNKNOWN_USER_DISPLAY_NAME = "Unknown user";
const NOTE_ACCESS_CLEANUP_PAGE_SIZE = 200;
const SCHEDULED_MESSAGE_CLEANUP_PAGE_SIZE = 100;
const SET_USER_BLOCK_TIMEOUT_SECONDS = 540;

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
 * Extracts public profile fields from a private user document.
 *
 * @param {DocumentSnapshot} userSnap The private users/{uid} document.
 * @param {string} fallbackName Name to use if the profile is blank.
 * @return {PublicProfileData} Public display fields.
 */
function publicProfileFromUser(
  userSnap: DocumentSnapshot,
  fallbackName: string,
): PublicProfileData {
  const rawName = userSnap.get("displayName");
  const displayName =
    typeof rawName === "string" && rawName.trim().length > 0 ?
      rawName.trim() :
      fallbackName;
  const rawPhoto = userSnap.get("photoUrl");
  const photoUrl =
    typeof rawPhoto === "string" && rawPhoto.trim().length > 0 ?
      rawPhoto.trim() :
      null;
  return {displayName, photoUrl, photoVersion: 1};
}

/**
 * Creates or refreshes a public profile mirror.
 *
 * @param {Transaction} tx The active transaction.
 * @param {DocumentReference} profileRef Public profile ref.
 * @param {DocumentSnapshot} profileSnap Current public profile snapshot.
 * @param {PublicProfileData} profile Public display fields.
 * @param {number} followerCountDelta Change to apply to followerCount.
 * @param {number} followingCountDelta Change to apply to followingCount.
 */
function upsertPublicProfile(
  tx: Transaction,
  profileRef: DocumentReference,
  profileSnap: DocumentSnapshot,
  profile: PublicProfileData,
  followerCountDelta: number,
  followingCountDelta: number,
): void {
  const followerCount = publicProfileCounter(profileSnap, "followerCount") +
    followerCountDelta;
  const followingCount = publicProfileCounter(profileSnap, "followingCount") +
    followingCountDelta;
  if (followerCount < 0 || followingCount < 0) {
    throw new HttpsError(
      "failed-precondition",
      "Public profile counters are inconsistent.",
    );
  }

  const storedCreatedAt = profileSnap.exists ?
    profileSnap.get("createdAt") :
    null;
  if (profileSnap.exists && !(storedCreatedAt instanceof Timestamp)) {
    throw new HttpsError(
      "failed-precondition",
      "Public profile timestamps are incomplete.",
    );
  }
  tx.set(
    profileRef,
    {
      displayName: profile.displayName,
      photoUrl: profile.photoUrl,
      photoVersion: profileSnap.exists &&
          typeof profileSnap.get("photoVersion") === "number" ?
        profileSnap.get("photoVersion") :
        profile.photoVersion,
      revision: profileSnap.exists &&
          typeof profileSnap.get("revision") === "number" ?
        profileSnap.get("revision") :
        1,
      followerCount,
      followingCount,
      createdAt: profileSnap.exists ?
        storedCreatedAt :
        FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
  );
}

/**
 * Returns a validated social counter from an existing public profile.
 *
 * @param {DocumentSnapshot} profileSnap Existing public profile.
 * @param {string} field Counter field to read.
 * @return {number} Current non-negative counter value.
 */
function publicProfileCounter(
  profileSnap: DocumentSnapshot,
  field: "followerCount" | "followingCount",
): number {
  if (!profileSnap.exists) return 0;
  const value = profileSnap.get(field);
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    throw new HttpsError(
      "failed-precondition",
      "Public profile counters are incomplete.",
    );
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
          await createUserNotice(targetUserId, {
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
 * Removes one user from every note created by the blocker.
 *
 * All active and archived notes are included. Two idempotent writes per note
 * keep each batch below the project's conservative 450-write limit.
 *
 * @param {string} blockerUid Note creator and block owner.
 * @param {string} blockedUid User whose access is being removed.
 */
async function removeBlockedUserFromOwnedNotes(
  blockerUid: string,
  blockedUid: string,
): Promise<void> {
  const db = asiaWorldContext().firestore;
  let cursor: DocumentSnapshot | undefined;
  let hasMore = true;

  while (hasMore) {
    let query = db
      .collection("places")
      .where("createdByUserId", "==", blockerUid)
      .orderBy(FieldPath.documentId())
      .limit(NOTE_ACCESS_CLEANUP_PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);
    const places = await query.get();
    if (places.empty) break;

    const batch = db.batch();
    for (const place of places.docs) {
      batch.update(place.ref, {
        maintainerIds: FieldValue.arrayRemove(blockedUid),
      });
      batch.delete(place.ref.collection("members").doc(blockedUid));
    }
    await batch.commit();
    for (const place of places.docs) {
      await cancelBlockedUserScheduledMessages(place.ref, blockedUid);
    }

    hasMore = places.size === NOTE_ACCESS_CLEANUP_PAGE_SIZE;
    cursor = places.docs[places.docs.length - 1];
  }
}

/**
 * Deletes a blocked user's unpublished scheduled messages from one note and
 * immediately releases their reserved message slots.
 *
 * @param {DocumentReference} placeRef Note document.
 * @param {string} blockedUid Blocked message author.
 */
async function cancelBlockedUserScheduledMessages(
  placeRef: DocumentReference,
  blockedUid: string,
): Promise<void> {
  const db = asiaWorldContext().firestore;
  let hasMore = true;

  while (hasMore) {
    const imagePaths = new Set<string>();
    const deletedCount = await db.runTransaction(async (tx) => {
      imagePaths.clear();
      const counterRef = placeRef.collection("counters").doc("messageSlots");
      const messagesQuery = placeRef
        .collection("messages")
        .where("userId", "==", blockedUid)
        .where("isPubliclyVisible", "==", false)
        .where("placeAggregateAppliedAt", "==", null)
        .limit(SCHEDULED_MESSAGE_CLEANUP_PAGE_SIZE);
      const [placeSnap, counterSnap, messagesSnap] = await Promise.all([
        tx.get(placeRef),
        tx.get(counterRef),
        tx.get(messagesQuery),
      ]);
      if (!placeSnap.exists || messagesSnap.empty) return 0;

      const scheduledMessages = messagesSnap.docs;
      for (const message of scheduledMessages) {
        const storedPaths = message.get("imageStoragePaths");
        if (Array.isArray(storedPaths)) {
          for (const path of storedPaths) {
            if (typeof path === "string" && path.length > 0) {
              imagePaths.add(path);
            }
          }
        }
        tx.delete(message.ref);
      }

      const publicCount =
        (placeSnap.get("messageCount") as number | undefined) ?? 0;
      const currentSlots = counterSnap.exists ?
        ((counterSnap.get("count") as number | undefined) ?? 0) :
        publicCount;
      const nextSlots = Math.max(0, currentSlots - scheduledMessages.length);
      tx.set(
        counterRef,
        {
          count: nextSlots,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );

      const expiresAt = placeSnap.get("expiresAt") as Timestamp | undefined;
      // A scheduled message reserves a slot before publication. Removing that
      // reservation may make a message-limit-closed note writable again.
      if (
        publicCount < MAX_MESSAGES_PER_THREAD &&
        nextSlots < MAX_MESSAGES_PER_THREAD &&
        placeSnap.get("closedReason") === "messageLimit" &&
        placeSnap.get("isArchived") !== true &&
        (!expiresAt || expiresAt.toMillis() > Date.now())
      ) {
        tx.update(placeRef, {
          isOpen: true,
          closedReason: FieldValue.delete(),
          closedAt: FieldValue.delete(),
        });
      }
      return scheduledMessages.length;
    });

    if (imagePaths.size > 0) {
      const bucket = asiaWorldContext().bucket;
      await Promise.all([...imagePaths].map(async (path) => {
        try {
          await bucket.file(path).delete({ignoreNotFound: true});
        } catch (error) {
          logger.warn(`Could not delete blocked message image ${path}.`, error);
        }
      }));
    }
    hasMore = deletedCount === SCHEDULED_MESSAGE_CLEANUP_PAGE_SIZE;
  }
}

/**
 * Sets the caller's final block state for another user.
 *
 * Block and follow state remain separate data, while the transaction enforces
 * the invariant that a blocked pair cannot retain a follow edge in either
 * direction.
 */
export const setUserBlock = onCall<SetUserBlockData>(
  {
    enforceAppCheck: true,
    region: REGION,
    timeoutSeconds: SET_USER_BLOCK_TIMEOUT_SECONDS,
  },
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const targetUserId = assertUserId(req.data?.targetUserId);
    const desiredBlocked = assertBlocked(req.data?.blocked);
    if (targetUserId === uid) {
      throw new HttpsError("invalid-argument", "You cannot block yourself.");
    }

    const db = asiaWorldContext().firestore;
    const blockRef = userBlockRef(db, uid, targetUserId);
    const blockerUserRef = db.collection("users").doc(uid);
    const blockedUserRef = db.collection("users").doc(targetUserId);
    const blockerProfileRef = db.collection("publicProfiles").doc(uid);
    const blockedProfileRef =
      db.collection("publicProfiles").doc(targetUserId);
    const outgoingEdgeRef = db
      .collection("socialEdges")
      .doc(socialEdgeId(uid, targetUserId));
    const incomingEdgeRef = db
      .collection("socialEdges")
      .doc(socialEdgeId(targetUserId, uid));

    await db.runTransaction(async (tx) => {
      const blockSnap = await tx.get(blockRef);
      if (!desiredBlocked) {
        if (blockSnap.exists) tx.delete(blockRef);
        return;
      }

      const [
        blockerUserSnap,
        blockedUserSnap,
        blockerProfileSnap,
        blockedProfileSnap,
        outgoingEdgeSnap,
        incomingEdgeSnap,
      ] = await Promise.all([
        tx.get(blockerUserRef),
        tx.get(blockedUserRef),
        tx.get(blockerProfileRef),
        tx.get(blockedProfileRef),
        tx.get(outgoingEdgeRef),
        tx.get(incomingEdgeRef),
      ]);

      if (!blockerUserSnap.exists) {
        throw new HttpsError("failed-precondition", "Caller profile missing.");
      }
      if (!blockedUserSnap.exists) {
        throw new HttpsError("not-found", "User not found.");
      }

      const outgoingEdge = outgoingEdgeSnap.exists ?
        parseSocialEdgeProjection(outgoingEdgeSnap, outgoingEdgeRef.id) :
        undefined;
      const incomingEdge = incomingEdgeSnap.exists ?
        parseSocialEdgeProjection(incomingEdgeSnap, incomingEdgeRef.id) :
        undefined;
      const removedOutgoing = outgoingEdge?.following === true;
      const removedIncoming = incomingEdge?.following === true;
      upsertPublicProfile(
        tx,
        blockerProfileRef,
        blockerProfileSnap,
        publicProfileFromUser(blockerUserSnap, UNKNOWN_USER_DISPLAY_NAME),
        removedIncoming ? -1 : 0,
        removedOutgoing ? -1 : 0,
      );
      upsertPublicProfile(
        tx,
        blockedProfileRef,
        blockedProfileSnap,
        publicProfileFromUser(blockedUserSnap, UNKNOWN_USER_DISPLAY_NAME),
        removedOutgoing ? -1 : 0,
        removedIncoming ? -1 : 0,
      );
      const removedAt = Timestamp.now();
      if (removedOutgoing && outgoingEdge !== undefined) {
        tx.set(outgoingEdgeRef, {
          ...nextSocialEdgeProjection(
            uid,
            targetUserId,
            false,
            outgoingEdge.revision + 1,
            removedAt,
            outgoingEdge,
          ),
        });
      }
      if (removedIncoming && incomingEdge !== undefined) {
        tx.set(incomingEdgeRef, {
          ...nextSocialEdgeProjection(
            targetUserId,
            uid,
            false,
            incomingEdge.revision + 1,
            removedAt,
            incomingEdge,
          ),
        });
      }
      if (!blockSnap.exists) {
        tx.set(blockRef, {createdAt: FieldValue.serverTimestamp()});
      }
    });

    if (desiredBlocked) {
      await removeBlockedUserFromOwnedNotes(uid, targetUserId);
    }
    return {blocked: desiredBlocked};
  },
);
