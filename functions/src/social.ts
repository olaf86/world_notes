import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {
  DocumentReference,
  DocumentSnapshot,
  FieldPath,
  FieldValue,
  getFirestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

import {REGION} from "./constants";
import {createUserNotice} from "./notices";
import {
  hasUserBlockBetweenInTransaction,
  userBlockRef,
} from "./userBlocks";

interface SetUserFollowData {
  targetUserId?: unknown;
  following?: unknown;
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

/**
 * Builds a stable edge document id without relying on uid delimiter safety.
 *
 * @param {string} followerUid The user creating the edge.
 * @param {string} followeeUid The user being followed.
 * @return {string} A Firestore document id for the edge.
 */
export function socialEdgeId(followerUid: string, followeeUid: string): string {
  return `${base64Url(followerUid)}.${base64Url(followeeUid)}`;
}

/**
 * Encodes a uid into a document-id-safe token.
 *
 * @param {string} value The uid to encode.
 * @return {string} A base64url token without padding.
 */
function base64Url(value: string): string {
  return Buffer.from(value, "utf8").toString("base64url");
}

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
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const targetUserId = assertUserId(req.data?.targetUserId);
    const desiredFollowing = assertFollowing(req.data?.following);
    if (targetUserId === uid) {
      throw new HttpsError("invalid-argument", "You cannot follow yourself.");
    }

    const db = getFirestore();
    const followerUserRef = db.collection("users").doc(uid);
    const followeeUserRef = db.collection("users").doc(targetUserId);
    const followerProfileRef = db.collection("publicProfiles").doc(uid);
    const followeeProfileRef =
      db.collection("publicProfiles").doc(targetUserId);
    const edgeRef = db
      .collection("socialEdges")
      .doc(socialEdgeId(uid, targetUserId));

    const result = await db.runTransaction(async (tx) => {
      const isBlocked = await hasUserBlockBetweenInTransaction(
        tx,
        db,
        uid,
        targetUserId,
      );
      const [
        followerUserSnap,
        followeeUserSnap,
        followerProfileSnap,
        followeeProfileSnap,
        edgeSnap,
      ] =
        await Promise.all([
          tx.get(followerUserRef),
          tx.get(followeeUserRef),
          tx.get(followerProfileRef),
          tx.get(followeeProfileRef),
          tx.get(edgeRef),
        ]);

      if (!followerUserSnap.exists) {
        throw new HttpsError("failed-precondition", "Caller profile missing.");
      }
      if (!followeeUserSnap.exists) {
        throw new HttpsError("not-found", "User not found.");
      }
      if (desiredFollowing && isBlocked) {
        throw new HttpsError(
          "failed-precondition",
          "You cannot follow a blocked user.",
          {reason: "user_blocked"},
        );
      }

      const isFollowing = edgeSnap.exists;
      if (isFollowing === desiredFollowing) {
        upsertPublicProfile(
          tx,
          followerProfileRef,
          followerProfileSnap,
          publicProfileFromUser(followerUserSnap, UNKNOWN_USER_DISPLAY_NAME),
          0,
          0,
        );
        upsertPublicProfile(
          tx,
          followeeProfileRef,
          followeeProfileSnap,
          publicProfileFromUser(followeeUserSnap, UNKNOWN_USER_DISPLAY_NAME),
          0,
          0,
        );
        return {
          following: desiredFollowing,
          createdFollow: false,
          followerName: publicProfileFromUser(
            followerUserSnap,
            UNKNOWN_USER_DISPLAY_NAME,
          ).displayName,
        };
      }

      if (desiredFollowing) {
        upsertPublicProfile(
          tx,
          followerProfileRef,
          followerProfileSnap,
          publicProfileFromUser(followerUserSnap, UNKNOWN_USER_DISPLAY_NAME),
          0,
          1,
        );
        upsertPublicProfile(
          tx,
          followeeProfileRef,
          followeeProfileSnap,
          publicProfileFromUser(followeeUserSnap, UNKNOWN_USER_DISPLAY_NAME),
          1,
          0,
        );
        tx.set(edgeRef, {
          followerUid: uid,
          followeeUid: targetUserId,
          createdAt: FieldValue.serverTimestamp(),
        });
      } else {
        upsertPublicProfile(
          tx,
          followerProfileRef,
          followerProfileSnap,
          publicProfileFromUser(followerUserSnap, UNKNOWN_USER_DISPLAY_NAME),
          0,
          -1,
        );
        upsertPublicProfile(
          tx,
          followeeProfileRef,
          followeeProfileSnap,
          publicProfileFromUser(followeeUserSnap, UNKNOWN_USER_DISPLAY_NAME),
          -1,
          0,
        );
        tx.delete(edgeRef);
      }

      return {
        following: desiredFollowing,
        createdFollow: desiredFollowing,
        followerName: publicProfileFromUser(
          followerUserSnap,
          UNKNOWN_USER_DISPLAY_NAME,
        ).displayName,
      };
    });

    if (result.createdFollow) {
      try {
        await createUserNotice(targetUserId, {
          category: "social",
          severity: "info",
          title: "New follower",
          body: `${result.followerName} followed you.`,
          sourceType: "userFollow",
          sourceId: uid,
          push: true,
        });
      } catch (error) {
        logger.error("setUserFollow: failed to create follower notice.", {
          followerUid: uid,
          followeeUid: targetUserId,
          error,
        });
      }
    }

    return {following: result.following};
  },
);

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
  const db = getFirestore();
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

    hasMore = places.size === NOTE_ACCESS_CLEANUP_PAGE_SIZE;
    cursor = places.docs[places.docs.length - 1];
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
  {enforceAppCheck: true, region: REGION},
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

    const db = getFirestore();
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

      const removedOutgoing = outgoingEdgeSnap.exists;
      const removedIncoming = incomingEdgeSnap.exists;
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
      if (removedOutgoing) tx.delete(outgoingEdgeRef);
      if (removedIncoming) tx.delete(incomingEdgeRef);
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
