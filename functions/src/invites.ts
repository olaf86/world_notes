import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {randomBytes} from "crypto";

import {REGION} from "./constants";
import {profileForMember} from "./userProfile";

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
  if (snap.get("createdByUserId") !== uid) {
    throw new HttpsError("permission-denied", "Only the owner can do this.");
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
    const inviteRef = db.collection("invites").doc(token);
    const inviteSnap = await inviteRef.get();
    if (!inviteSnap.exists || inviteSnap.get("revoked") === true) {
      throw new HttpsError(
        "not-found",
        "This invite link is invalid or has been revoked.",
      );
    }

    const placeId = inviteSnap.get("placeId") as string;
    const memberRef = db
      .collection("places")
      .doc(placeId)
      .collection("members")
      .doc(uid);
    const profile = await profileForMember(
      uid,
      req.auth?.token.name,
      req.auth?.token.email,
    );

    const batch = db.batch();
    batch.set(
      memberRef,
      {
        userId: uid,
        invited: true,
        grantedAt: FieldValue.serverTimestamp(),
        displayName: profile.displayName,
        email: profile.email,
      },
      {merge: true},
    );
    batch.update(inviteRef, {useCount: FieldValue.increment(1)});
    await batch.commit();

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

    await getFirestore()
      .collection("places")
      .doc(placeId)
      .collection("members")
      .doc(userId)
      .delete();
    return {ok: true};
  },
);
