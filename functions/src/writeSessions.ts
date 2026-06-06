import {onCall, HttpsError} from "firebase-functions/v2/https";
import {
  DocumentSnapshot,
  getFirestore,
  FieldValue,
  Timestamp,
} from "firebase-admin/firestore";

import {
  MAX_MESSAGES_PER_THREAD,
  REGION,
  WRITE_SESSION_TTL_MINUTES,
} from "./constants";

/**
 * Returns true when [uid] may read/access the note represented by [placeSnap].
 *
 * Mirrors Firestore Rules' canAccessNote(): public notes are available to
 * signed-in users; private notes require ownership or a still-valid membership.
 *
 * @param {string} placeId The note id.
 * @param {string} uid The caller uid.
 * @param {DocumentSnapshot} placeSnap The already-loaded place snapshot.
 * @return {Promise<boolean>} Whether the caller may access the note.
 */
async function canAccessNote(
  placeId: string,
  uid: string,
  placeSnap: DocumentSnapshot,
): Promise<boolean> {
  if (placeSnap.get("visibility") !== "private") return true;
  if (placeSnap.get("createdByUserId") === uid) return true;

  const memberSnap = await getFirestore()
    .collection("places")
    .doc(placeId)
    .collection("members")
    .doc(uid)
    .get();
  if (!memberSnap.exists) return false;

  return memberSnap.get("invited") === true ||
    memberSnap.get("viaPasswordVersion") === placeSnap.get("passwordVersion");
}

/**
 * Creates a short-lived write session for a note.
 *
 * Firestore Rules require this session before accepting a direct message
 * write. My Notes never requests a session, so it stays read-only even though
 * it reuses the same note screen.
 */
export const createWriteSession = onCall<{placeId?: unknown}>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const {placeId} = req.data ?? {};
    if (typeof placeId !== "string" || placeId.length === 0) {
      throw new HttpsError("invalid-argument", "placeId is required.");
    }

    const db = getFirestore();
    const placeRef = db.collection("places").doc(placeId);
    const placeSnap = await placeRef.get();
    if (!placeSnap.exists) {
      throw new HttpsError("not-found", "Note not found.");
    }

    if (!(await canAccessNote(placeId, uid, placeSnap))) {
      throw new HttpsError("permission-denied", "You cannot access this note.");
    }

    if (placeSnap.get("isOpen") !== true) {
      throw new HttpsError("failed-precondition", "This note is closed.");
    }
    if (placeSnap.get("isArchived") === true) {
      throw new HttpsError("failed-precondition", "This note is archived.");
    }
    const expiresAt = placeSnap.get("expiresAt") as Timestamp | undefined;
    if (expiresAt && expiresAt.toMillis() <= Date.now()) {
      throw new HttpsError("failed-precondition", "This note has expired.");
    }
    const messageCount = (placeSnap.get("messageCount") as number) ?? 0;
    if (messageCount >= MAX_MESSAGES_PER_THREAD) {
      throw new HttpsError("resource-exhausted", "This note is full.");
    }

    await placeRef.collection("writeSessions").doc(uid).set({
      uid,
      placeId,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(
        Date.now() + WRITE_SESSION_TTL_MINUTES * 60 * 1000,
      ),
    });

    return {ok: true};
  },
);
