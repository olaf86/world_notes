/* eslint-disable require-jsdoc */
import {onCall, HttpsError} from "./platform/worldCallable";
import {
  DocumentSnapshot,
  Timestamp,
} from "firebase-admin/firestore";

import {assertAccountSafetyAllows} from "./accountSafety";
import {REGION} from "./constants";
import {
  assertLiked,
  hasValidMembership,
  isPublishedReadablePlace,
  likeEdgeData,
  likedStateOf,
  nextLikeCount,
} from "./likeHelpers";
import {canMaintainNote, isNoteCreator} from "./noteMaintenance";
import {hasUserBlockBetweenInTransaction} from "./userBlocks";

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
  async (req, world) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const placeId = assertPlaceId(req.data?.placeId);
    const desiredLiked = assertLiked(req.data?.liked);
    const db = world.firestore;
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
      if (desiredLiked) {
        await assertAccountSafetyAllows(
          tx,
          db,
          uid,
          "participation",
          Timestamp.fromMillis(nowMs),
        );
      }
      if (!canLikeNote(placeSnap, memberSnap, uid, nowMs)) {
        throw new HttpsError(
          "permission-denied",
          "You cannot like this note.",
        );
      }

      const creatorUid =
        placeSnap.get("createdByUserId") as string | undefined;
      if (
        desiredLiked &&
        creatorUid &&
        await hasUserBlockBetweenInTransaction(tx, db, uid, creatorUid)
      ) {
        throw new HttpsError(
          "permission-denied",
          "You cannot like this note.",
          {reason: "user_blocked"},
        );
      }
      const likeSnap = await tx.get(likeRef);
      const currentlyLiked = likedStateOf(likeSnap);
      const currentCount = placeSnap.get("likeCount") as number;
      const result = nextLikeCount({
        currentCount,
        currentlyLiked,
        desiredLiked,
      });
      if (!result.changed) {
        return {liked: desiredLiked, likeCount: result.likeCount};
      }

      tx.set(
        likeRef,
        likeEdgeData({
          uid,
          liked: desiredLiked,
          extra: {placeId},
        }),
        {merge: true},
      );
      tx.update(placeRef, {likeCount: result.likeCount});
      return {liked: desiredLiked, likeCount: result.likeCount};
    });
  },
);
