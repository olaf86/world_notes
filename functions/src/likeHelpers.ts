/* eslint-disable require-jsdoc */
import {HttpsError} from "firebase-functions/v2/https";
import {
  DocumentSnapshot,
  FieldValue,
  Timestamp,
} from "firebase-admin/firestore";

interface LikeEdgeDataParams {
  uid: string;
  liked: boolean;
  extra?: Record<string, unknown>;
}

interface NextLikeCountParams {
  currentCount: number;
  currentlyLiked: boolean;
  desiredLiked: boolean;
}

export function assertLiked(value: unknown): boolean {
  if (typeof value !== "boolean") {
    throw new HttpsError("invalid-argument", "liked must be a boolean.");
  }
  return value;
}

export function isPublishedReadablePlace(
  placeSnap: DocumentSnapshot,
  nowMs: number,
): boolean {
  const publishAt = placeSnap.get("publishAt") as Timestamp | undefined;
  const expiresAt = placeSnap.get("expiresAt") as Timestamp | undefined;
  return placeSnap.get("isArchived") !== true &&
    publishAt != null &&
    expiresAt != null &&
    publishAt.toMillis() <= nowMs &&
    expiresAt.toMillis() > nowMs;
}

export function hasValidMembership(
  placeSnap: DocumentSnapshot,
  memberSnap: DocumentSnapshot | null,
): boolean {
  if (!memberSnap?.exists) return false;
  return memberSnap.get("invited") === true ||
    memberSnap.get("viaPasswordVersion") === placeSnap.get("passwordVersion");
}

export function likedStateOf(likeSnap: DocumentSnapshot): boolean {
  return likeSnap.exists && likeSnap.get("liked") === true;
}

export function nextLikeCount({
  currentCount,
  currentlyLiked,
  desiredLiked,
}: NextLikeCountParams): {changed: boolean; likeCount: number} {
  if (currentlyLiked === desiredLiked) {
    return {changed: false, likeCount: currentCount};
  }
  const increment = desiredLiked ? 1 : -1;
  return {changed: true, likeCount: Math.max(0, currentCount + increment)};
}

export function likeEdgeData({
  uid,
  liked,
  extra = {},
}: LikeEdgeDataParams): Record<string, unknown> {
  return {
    userId: uid,
    ...extra,
    liked,
    likedAt: liked ? FieldValue.serverTimestamp() : null,
    updatedAt: FieldValue.serverTimestamp(),
  };
}
