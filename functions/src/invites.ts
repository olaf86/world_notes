import {onCall, HttpsError} from "firebase-functions/v2/https";
import {
  DocumentSnapshot,
  getFirestore,
  FieldValue,
} from "firebase-admin/firestore";
import {randomBytes} from "crypto";

import {REGION} from "./constants";
import {profileForMember} from "./userProfile";

/**
 * Reads the note owner id array, tolerating legacy docs without it.
 *
 * @param {DocumentSnapshot} placeSnap The note document.
 * @return {string[]} Owner ids stored on the note.
 */
function ownerIdsOf(placeSnap: DocumentSnapshot): string[] {
  const ownerIds = placeSnap.get("ownerIds") as string[] | undefined;
  return ownerIds ?? [];
}

/**
 * Returns whether uid is the creator or a co-owner of the note.
 *
 * @param {DocumentSnapshot} placeSnap The note document.
 * @param {string} uid The user id to check.
 * @return {boolean} Whether the user owns the note.
 */
function isOwner(placeSnap: DocumentSnapshot, uid: string): boolean {
  return placeSnap.get("createdByUserId") === uid ||
    ownerIdsOf(placeSnap).includes(uid);
}

/**
 * Loads a place and asserts the caller owns it. Throws otherwise.
 *
 * @param {string} placeId The note's id.
 * @param {string} uid The caller's uid.
 */
async function assertOwner(placeId: string, uid: string) {
  const db = getFirestore();
  const snap = await db.collection("places").doc(placeId).get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Note not found.");
  }
  if (!isOwner(snap, uid)) {
    throw new HttpsError("permission-denied", "Only the owner can do this.");
  }
  if (snap.get("isArchived") === true) {
    throw new HttpsError("failed-precondition", "This note is archived.");
  }
}

/**
 * Returns the active reusable invite token for a place, if one exists.
 *
 * @param {string} placeId The note's id.
 */
async function activeInviteToken(placeId: string): Promise<string | null> {
  const existing = await getFirestore()
    .collection("invites")
    .where("placeId", "==", placeId)
    .limit(10)
    .get();
  const active = existing.docs.find((d) => d.get("revoked") !== true);
  return active?.id ?? null;
}

/**
 * Owner-only: returns the note's active reusable invite token, if one exists.
 * Unlike createInviteLink, this does not create a new invite.
 */
export const getInviteLink = onCall<{placeId?: unknown}>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
    const {placeId} = req.data ?? {};
    if (typeof placeId !== "string" || placeId.length === 0) {
      throw new HttpsError("invalid-argument", "placeId is required.");
    }
    await assertOwner(placeId, uid);

    return {token: await activeInviteToken(placeId)};
  },
);

/**
 * Owner-only: returns the note's reusable invite token, creating one if none
 * is active. The token is the secret (high-entropy doc id) and lives in the
 * server-only `invites` collection — never on the client-readable place doc.
 */
export const createInviteLink = onCall<{placeId?: unknown}>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
    const {placeId} = req.data ?? {};
    if (typeof placeId !== "string" || placeId.length === 0) {
      throw new HttpsError("invalid-argument", "placeId is required.");
    }
    await assertOwner(placeId, uid);

    const db = getFirestore();
    // Reuse an existing active token (one reusable link per note).
    const active = await activeInviteToken(placeId);
    if (active) return {token: active};

    const token = randomBytes(16).toString("base64url");
    await db.collection("invites").doc(token).set({
      placeId,
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      revoked: false,
      useCount: 0,
    });
    return {token};
  },
);

/**
 * Redeems an invite token for the signed-in user: grants invited membership
 * (which survives password changes) and returns the placeId to navigate to.
 * Idempotent — claiming twice just keeps the grant.
 */
export const claimInvite = onCall<{token?: unknown}>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
    const {token} = req.data ?? {};
    if (typeof token !== "string" || token.length === 0) {
      throw new HttpsError("invalid-argument", "token is required.");
    }

    const db = getFirestore();
    const profile = await profileForMember(
      uid,
      req.auth?.token.name,
    );
    const inviteRef = db.collection("invites").doc(token);
    const placeId = await db.runTransaction(async (tx) => {
      const inviteSnap = await tx.get(inviteRef);
      if (!inviteSnap.exists || inviteSnap.get("revoked") === true) {
        throw new HttpsError(
          "not-found",
          "This invite link is invalid or has been revoked.",
        );
      }

      const resolvedPlaceId = inviteSnap.get("placeId") as string;
      const placeRef = db.collection("places").doc(resolvedPlaceId);
      const placeSnap = await tx.get(placeRef);
      if (!placeSnap.exists) {
        throw new HttpsError(
          "not-found",
          "This invite link is invalid or has been revoked.",
        );
      }
      const expiresAt = placeSnap.get("expiresAt");
      if (
        placeSnap.get("isArchived") === true ||
        !expiresAt ||
        expiresAt.toMillis() <= Date.now()
      ) {
        throw new HttpsError(
          "not-found",
          "This invite link is invalid or has been revoked.",
        );
      }

      tx.set(
        placeRef.collection("members").doc(uid),
        {
          userId: uid,
          invited: true,
          grantedAt: FieldValue.serverTimestamp(),
          displayName: profile.displayName,
        },
        {merge: true},
      );
      tx.update(inviteRef, {useCount: FieldValue.increment(1)});
      return resolvedPlaceId;
    });

    return {placeId};
  },
);

/**
 * Owner-only: revokes the note's invite link(s), so the shared link stops
 * working. Existing members keep their access (use revokeNoteAccess to remove
 * an individual).
 */
export const revokeInvite = onCall<{placeId?: unknown}>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
    const {placeId} = req.data ?? {};
    if (typeof placeId !== "string" || placeId.length === 0) {
      throw new HttpsError("invalid-argument", "placeId is required.");
    }
    await assertOwner(placeId, uid);

    const db = getFirestore();
    const tokens = await db
      .collection("invites")
      .where("placeId", "==", placeId)
      .get();
    const batch = db.batch();
    for (const doc of tokens.docs) {
      if (doc.get("revoked") !== true) {
        batch.update(doc.ref, {revoked: true});
      }
    }
    await batch.commit();
    return {ok: true};
  },
);

/**
 * Owner-only: removes a single member's access grant.
 */
export const revokeNoteAccess = onCall<{placeId?: unknown; userId?: unknown}>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
    const {placeId, userId} = req.data ?? {};
    if (
      typeof placeId !== "string" ||
      placeId.length === 0 ||
      typeof userId !== "string" ||
      userId.length === 0
    ) {
      throw new HttpsError("invalid-argument", "placeId/userId required.");
    }
    await assertOwner(placeId, uid);

    const db = getFirestore();
    const placeRef = db.collection("places").doc(placeId);
    const placeSnap = await placeRef.get();
    if (!placeSnap.exists) {
      throw new HttpsError("not-found", "Note not found.");
    }
    if (isOwner(placeSnap, userId)) {
      throw new HttpsError(
        "failed-precondition",
        "Remove owner access before removing this member.",
      );
    }

    await placeRef
      .collection("members")
      .doc(userId)
      .delete();
    return {ok: true};
  },
);

/**
 * Owner-only: promotes an existing member to a co-owner.
 */
export const grantNoteOwnership = onCall<{
  placeId?: unknown;
  userId?: unknown;
}>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
    const {placeId, userId} = req.data ?? {};
    if (
      typeof placeId !== "string" ||
      placeId.length === 0 ||
      typeof userId !== "string" ||
      userId.length === 0
    ) {
      throw new HttpsError("invalid-argument", "placeId/userId required.");
    }

    const db = getFirestore();
    const placeRef = db.collection("places").doc(placeId);
    await db.runTransaction(async (tx) => {
      const placeSnap = await tx.get(placeRef);
      if (!placeSnap.exists) {
        throw new HttpsError("not-found", "Note not found.");
      }
      if (!isOwner(placeSnap, uid)) {
        throw new HttpsError(
          "permission-denied",
          "Only the owner can do this.",
        );
      }
      if (placeSnap.get("isArchived") === true) {
        throw new HttpsError("failed-precondition", "This note is archived.");
      }

      const memberRef = placeRef.collection("members").doc(userId);
      const memberSnap = await tx.get(memberRef);
      if (!memberSnap.exists) {
        throw new HttpsError(
          "failed-precondition",
          "Only people with access can become owners.",
        );
      }

      tx.update(placeRef, {ownerIds: FieldValue.arrayUnion(userId)});
      tx.set(memberRef, {isOwner: true}, {merge: true});
    });

    return {ok: true};
  },
);

/**
 * Owner-only: removes co-owner status from a member.
 */
export const revokeNoteOwnership = onCall<{
  placeId?: unknown;
  userId?: unknown;
}>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
    const {placeId, userId} = req.data ?? {};
    if (
      typeof placeId !== "string" ||
      placeId.length === 0 ||
      typeof userId !== "string" ||
      userId.length === 0
    ) {
      throw new HttpsError("invalid-argument", "placeId/userId required.");
    }
    if (userId === uid) {
      throw new HttpsError(
        "failed-precondition",
        "Ask another owner to remove your owner access.",
      );
    }

    const db = getFirestore();
    const placeRef = db.collection("places").doc(placeId);
    await db.runTransaction(async (tx) => {
      const placeSnap = await tx.get(placeRef);
      if (!placeSnap.exists) {
        throw new HttpsError("not-found", "Note not found.");
      }
      if (!isOwner(placeSnap, uid)) {
        throw new HttpsError(
          "permission-denied",
          "Only the owner can do this.",
        );
      }
      if (placeSnap.get("createdByUserId") === userId) {
        throw new HttpsError(
          "failed-precondition",
          "The note creator must remain an owner.",
        );
      }

      const memberRef = placeRef.collection("members").doc(userId);
      const memberSnap = await tx.get(memberRef);
      tx.update(placeRef, {ownerIds: FieldValue.arrayRemove(userId)});
      if (memberSnap.exists) {
        tx.set(memberRef, {isOwner: false}, {merge: true});
      }
    });

    return {ok: true};
  },
);
