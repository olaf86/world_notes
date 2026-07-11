/* eslint-disable require-jsdoc */
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {
  DocumentSnapshot,
  FieldValue,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";

import {REGION} from "./constants";
import {canMaintainNote, isNoteCreator} from "./noteMaintenance";

interface SetNoteLikeData {
  placeId?: unknown;
  liked?: unknown;
}

function assertPlaceId(value: unknown): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", "placeId is required.");
  }
  return value.trim();
}

function assertLiked(value: unknown): boolean {
  if (typeof value !== "boolean") {
    throw new HttpsError("invalid-argument", "liked must be a boolean.");
  }
  return value;
}

function isPublishedReadablePlace(
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

function hasValidMembership(
  placeSnap: DocumentSnapshot,
  memberSnap: DocumentSnapshot | null,
): boolean {
  if (!memberSnap?.exists) return false;
  return memberSnap.get("invited") === true ||
    memberSnap.get("viaPasswordVersion") === placeSnap.get("passwordVersion");
}

function canLikeNote(
  placeSnap: DocumentSnapshot,
  memberSnap: DocumentSnapshot | null,
  uid: string,
  nowMs: number,
): boolean {
  if (!isPublishedReadablePlace(placeSnap, nowMs)) return false;
  if (isNoteCreator(placeSnap, uid)) return false;
  if (placeSnap.get("visibility") !== "private") return true;
  if (canMaintainNote(placeSnap, uid)) return true;
  return hasValidMembership(placeSnap, memberSnap);
}

export const setNoteLike = onCall<SetNoteLikeData>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const placeId = assertPlaceId(req.data?.placeId);
    const desiredLiked = assertLiked(req.data?.liked);
    const db = getFirestore();
    const placeRef = db.collection("places").doc(placeId);
    const likeRef = placeRef.collection("likes").doc(uid);
    const memberRef = placeRef.collection("members").doc(uid);
    const nowMs = Date.now();

    return db.runTransaction(async (tx) => {
      const placeSnap = await tx.get(placeRef);
      if (!placeSnap.exists) {
        throw new HttpsError("not-found", "Note not found.");
      }
      const memberSnap =
        placeSnap.get("visibility") === "private" &&
          !canMaintainNote(placeSnap, uid) ?
          await tx.get(memberRef) :
          null;
      if (!canLikeNote(placeSnap, memberSnap, uid, nowMs)) {
        throw new HttpsError(
          "permission-denied",
          "You cannot like this note.",
        );
      }

      const likeSnap = await tx.get(likeRef);
      const currentlyLiked = likeSnap.exists &&
        likeSnap.get("liked") === true;
      const currentCount = placeSnap.get("likeCount") as number;
      if (currentlyLiked === desiredLiked) {
        return {liked: desiredLiked, likeCount: currentCount};
      }

      const increment = desiredLiked ? 1 : -1;
      const nextCount = Math.max(0, currentCount + increment);
      tx.set(
        likeRef,
        {
          userId: uid,
          placeId,
          liked: desiredLiked,
          likedAt: desiredLiked ? FieldValue.serverTimestamp() : null,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      tx.update(placeRef, {likeCount: nextCount});
      return {liked: desiredLiked, likeCount: nextCount};
    });
  },
);
