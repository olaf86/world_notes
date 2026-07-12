import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {
  DocumentReference,
  DocumentSnapshot,
  FieldValue,
  getFirestore,
  Transaction,
} from "firebase-admin/firestore";

import {REGION} from "./constants";
import {createUserNotice} from "./notices";

interface SetUserFollowData {
  targetUserId?: unknown;
  following?: unknown;
}

interface PublicProfileData {
  displayName: string;
  photoUrl: string | null;
}

const MAX_UID_LENGTH = 128;
const UNKNOWN_USER_DISPLAY_NAME = "Unknown user";

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
  return {displayName, photoUrl};
}

/**
 * Creates or refreshes a public profile mirror.
 *
 * @param {Transaction} tx The active transaction.
 * @param {DocumentReference} profileRef Public profile ref.
 * @param {PublicProfileData} profile Public display fields.
 * @param {number} followerCountDelta Change to apply to followerCount.
 * @param {number} followingCountDelta Change to apply to followingCount.
 */
function upsertPublicProfile(
  tx: Transaction,
  profileRef: DocumentReference,
  profile: PublicProfileData,
  followerCountDelta: number,
  followingCountDelta: number,
): void {
  tx.set(
    profileRef,
    {
      displayName: profile.displayName,
      photoUrl: profile.photoUrl,
      followerCount: FieldValue.increment(followerCountDelta),
      followingCount: FieldValue.increment(followingCountDelta),
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
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
      const [followerUserSnap, followeeUserSnap, edgeSnap] =
        await Promise.all([
          tx.get(followerUserRef),
          tx.get(followeeUserRef),
          tx.get(edgeRef),
        ]);

      if (!followerUserSnap.exists) {
        throw new HttpsError("failed-precondition", "Caller profile missing.");
      }
      if (!followeeUserSnap.exists) {
        throw new HttpsError("not-found", "User not found.");
      }

      const isFollowing = edgeSnap.exists;
      if (isFollowing === desiredFollowing) {
        upsertPublicProfile(
          tx,
          followerProfileRef,
          publicProfileFromUser(followerUserSnap, UNKNOWN_USER_DISPLAY_NAME),
          0,
          0,
        );
        upsertPublicProfile(
          tx,
          followeeProfileRef,
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
          publicProfileFromUser(followerUserSnap, UNKNOWN_USER_DISPLAY_NAME),
          0,
          1,
        );
        upsertPublicProfile(
          tx,
          followeeProfileRef,
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
          publicProfileFromUser(followerUserSnap, UNKNOWN_USER_DISPLAY_NAME),
          0,
          -1,
        );
        upsertPublicProfile(
          tx,
          followeeProfileRef,
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
