/* eslint-disable require-jsdoc */
import {onCall, HttpsError} from "./platform/worldCallable";
import {
  DocumentSnapshot,
  FieldValue,
  Timestamp,
} from "firebase-admin/firestore";

import {REGION} from "./constants";
import {assertAccountSafetyAllows} from "./accountSafety";
import {canMaintainNote} from "./noteMaintenance";
import {hasUserBlockBetweenInTransaction} from "./userBlocks";

interface RecordNoteVisitData {
  placeId?: unknown;
}

interface SetFootprintEnabledData {
  placeId?: unknown;
  enabled?: unknown;
}

function placeIdOf(value: unknown): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", "placeId is required.");
  }
  return value.trim();
}

function stringOrNull(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function hasValidMembership(
  placeSnap: DocumentSnapshot,
  memberSnap: DocumentSnapshot | null,
): boolean {
  if (!memberSnap?.exists) return false;
  return memberSnap.get("invited") === true ||
    memberSnap.get("viaPasswordVersion") === placeSnap.get("passwordVersion");
}

function isPubliclyReadablePlace(
  placeSnap: DocumentSnapshot,
  nowMillis: number,
): boolean {
  const publishAt = placeSnap.get("publishAt") as Timestamp | undefined;
  const expiresAt = placeSnap.get("expiresAt") as Timestamp | undefined;
  return placeSnap.get("isArchived") !== true &&
    placeSnap.get("isModerationHidden") === false &&
    publishAt != null &&
    expiresAt != null &&
    publishAt.toMillis() <= nowMillis &&
    expiresAt.toMillis() > nowMillis;
}

function canAccessNote({
  placeSnap,
  memberSnap,
  uid,
  nowMillis,
}: {
  placeSnap: DocumentSnapshot;
  memberSnap: DocumentSnapshot | null;
  uid: string;
  nowMillis: number;
}): boolean {
  if (placeSnap.get("isModerationHidden") !== false) return false;
  if (canMaintainNote(placeSnap, uid)) return true;
  if (!isPubliclyReadablePlace(placeSnap, nowMillis)) return false;
  if (placeSnap.get("visibility") !== "private") return true;
  return hasValidMembership(placeSnap, memberSnap);
}

export const recordNoteVisit = onCall<RecordNoteVisitData>(
  {enforceAppCheck: true, region: REGION},
  async (req, world) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const placeId = placeIdOf(req.data?.placeId);
    const db = world.firestore;
    const placeRef = db.collection("places").doc(placeId);
    const userRef = db.collection("users").doc(uid);
    const noteStateRef = userRef.collection("noteStates").doc(placeId);
    const memberRef = placeRef.collection("members").doc(uid);
    const visitorRef = placeRef.collection("visitors").doc(uid);
    const nowMillis = Date.now();

    await db.runTransaction(async (tx) => {
      const placeSnap = await tx.get(placeRef);
      await assertAccountSafetyAllows(
        tx,
        db,
        uid,
        "participation",
        Timestamp.fromMillis(nowMillis),
      );
      if (!placeSnap.exists) {
        throw new HttpsError("not-found", "Note not found.");
      }
      const creatorUid =
        placeSnap.get("createdByUserId") as string | undefined;
      if (
        creatorUid &&
        await hasUserBlockBetweenInTransaction(tx, db, uid, creatorUid)
      ) {
        throw new HttpsError(
          "permission-denied",
          "You cannot access this note.",
          {reason: "user_blocked"},
        );
      }
      const isMaintainer = canMaintainNote(placeSnap, uid);
      const memberSnap =
        placeSnap.get("visibility") === "private" && !isMaintainer ?
          await tx.get(memberRef) :
          null;
      if (!canAccessNote({placeSnap, memberSnap, uid, nowMillis})) {
        throw new HttpsError(
          "permission-denied",
          "You cannot access this note.",
        );
      }

      const footprintEnabled = placeSnap.get("footprintEnabled") !== false;
      const [userSnap, visitorSnap] = footprintEnabled ?
        await Promise.all([tx.get(userRef), tx.get(visitorRef)]) :
        [null, null];

      tx.set(
        noteStateRef,
        {
          lastSeenMessageCount:
            (placeSnap.get("messageCount") as number | undefined) ?? 0,
          lastOpenedAt: FieldValue.serverTimestamp(),
          discoverySeenAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      if (!footprintEnabled || userSnap == null || visitorSnap == null) return;

      const token = (req.auth?.token ?? {}) as Record<string, unknown>;
      const displayName =
        stringOrNull(userSnap.get("displayName")) ??
        stringOrNull(token.name);
      const photoUrl =
        stringOrNull(userSnap.get("photoUrl")) ??
        stringOrNull(token.picture);
      const firstVisitedAt =
        visitorSnap.exists ?
          visitorSnap.get("firstVisitedAt") ?? FieldValue.serverTimestamp() :
          FieldValue.serverTimestamp();

      tx.set(
        visitorRef,
        {
          userId: uid,
          displayName,
          photoUrl,
          firstVisitedAt,
          lastVisitedAt: FieldValue.serverTimestamp(),
          visitCount: FieldValue.increment(1),
          isMaintainer,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      if (!visitorSnap.exists) {
        tx.update(placeRef, {
          visitorCount: FieldValue.increment(1),
        });
      }
    });
  },
);

export const setFootprintEnabled = onCall<SetFootprintEnabledData>(
  {enforceAppCheck: true, region: REGION},
  async (req, world) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const placeId = placeIdOf(req.data?.placeId);
    const enabled = req.data?.enabled;
    if (typeof enabled !== "boolean") {
      throw new HttpsError("invalid-argument", "enabled is required.");
    }

    const db = world.firestore;
    const placeRef = db.collection("places").doc(placeId);
    await db.runTransaction(async (tx) => {
      const placeSnap = await tx.get(placeRef);
      await assertAccountSafetyAllows(
        tx,
        db,
        uid,
        "contentWrite",
        Timestamp.now(),
      );
      if (!placeSnap.exists) {
        throw new HttpsError("not-found", "Note not found.");
      }
      const creatorUid =
        placeSnap.get("createdByUserId") as string | undefined;
      if (
        creatorUid &&
        await hasUserBlockBetweenInTransaction(tx, db, uid, creatorUid)
      ) {
        throw new HttpsError(
          "permission-denied",
          "You cannot access this note.",
          {reason: "user_blocked"},
        );
      }
      if (!canMaintainNote(placeSnap, uid)) {
        throw new HttpsError(
          "permission-denied",
          "Only note maintainers can change footprints.",
        );
      }
      tx.update(placeRef, {
        footprintEnabled: enabled,
        footprintUpdatedAt: FieldValue.serverTimestamp(),
        footprintUpdatedBy: uid,
      });
    });
  },
);
