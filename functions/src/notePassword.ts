import {onCall, HttpsError} from "./platform/worldCallable";
import {
  FieldValue,
  Timestamp,
} from "firebase-admin/firestore";

import {REGION} from "./constants";
import {asiaWorldContext} from "./platform/worldContext";
import {
  hashLockSecret,
  MAX_LOCK_HINT_LENGTH,
  NOTE_PW_PEPPER,
  parseLockType,
  validateLockSecret,
  verifyLockSecret,
} from "./noteLock";
import {canChangeNoteLock} from "./noteMaintenance";
import {profileForMember} from "./userProfile";
import {hasUserBlockBetween} from "./userBlocks";

// Online brute-force protection for unlockNote.
const MAX_ATTEMPTS = 5;
const ATTEMPT_WINDOW_MS = 15 * 60 * 1000; // 15 minutes

/**
 * Creator-only: set or change a note's lock secret (locks it as private).
 *
 * The hash lives in places/{id}/secret/auth, which clients can never read,
 * and is keyed by a server pepper so a Firestore leak alone can't crack it.
 * Bumping passwordVersion invalidates every remembered unlock from the old
 * secret (members carry the version they unlocked with).
 */
export const setNotePassword = onCall<{
  placeId?: unknown;
  password?: unknown;
  lockType?: unknown;
  lockHint?: unknown;
}>(
  {secrets: [NOTE_PW_PEPPER], enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const {placeId, password, lockType, lockHint} = req.data ?? {};
    if (typeof placeId !== "string" || placeId.length === 0) {
      throw new HttpsError("invalid-argument", "placeId is required.");
    }
    if (typeof password !== "string") {
      throw new HttpsError("invalid-argument", "password is required.");
    }
    const requestedLockType = parseLockType(lockType);
    if (requestedLockType == null) {
      throw new HttpsError("invalid-argument", "Invalid lock type.");
    }
    const weakness = validateLockSecret(password, requestedLockType);
    if (weakness) throw new HttpsError("invalid-argument", weakness);
    if (
      lockHint != null &&
      (typeof lockHint !== "string" || lockHint.length > MAX_LOCK_HINT_LENGTH)
    ) {
      throw new HttpsError("invalid-argument", "Invalid hint.");
    }

    const db = asiaWorldContext().firestore;
    const placeRef = db.collection("places").doc(placeId);
    const placeSnap = await placeRef.get();
    if (!placeSnap.exists) {
      throw new HttpsError("not-found", "Note not found.");
    }
    if (!canChangeNoteLock(placeSnap, uid)) {
      throw new HttpsError(
        "permission-denied",
        "Only the note creator can change this lock.",
      );
    }

    const newVersion = ((placeSnap.get("passwordVersion") as number) ?? 0) + 1;
    const hash = await hashLockSecret(password);

    const batch = db.batch();
    batch.set(placeRef.collection("secret").doc("auth"), {
      hash,
      passwordVersion: newVersion,
    });
    batch.update(placeRef, {
      visibility: "private",
      passwordVersion: newVersion,
      lockType: requestedLockType,
      lockHint:
        typeof lockHint === "string" && lockHint.trim().length > 0 ?
          lockHint.trim() :
          FieldValue.delete(),
    });
    await batch.commit();

    return {ok: true, passwordVersion: newVersion};
  },
);

/**
 * Verify a password or pattern and, on success, grant remembered access.
 *
 * Rate-limited per user+note to blunt online brute force. On success a
 * members/{uid} doc records the passwordVersion unlocked with, so the user
 * is not prompted again until the creator changes the secret.
 */
export const unlockNote = onCall<{placeId?: unknown; password?: unknown}>(
  {secrets: [NOTE_PW_PEPPER], enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const {placeId, password} = req.data ?? {};
    if (
      typeof placeId !== "string" ||
      placeId.length === 0 ||
      typeof password !== "string"
    ) {
      throw new HttpsError("invalid-argument", "placeId/password required.");
    }

    const db = asiaWorldContext().firestore;
    const placeRef = db.collection("places").doc(placeId);
    const attemptRef = placeRef.collection("attempts").doc(uid);
    const placeSnap = await placeRef.get();
    if (!placeSnap.exists) {
      throw new HttpsError("not-found", "Note not found.");
    }
    if (placeSnap.get("isModerationHidden") !== false) {
      throw new HttpsError("not-found", "Note not found.");
    }
    const creatorUid =
      placeSnap.get("createdByUserId") as string | undefined;
    if (
      creatorUid &&
      await hasUserBlockBetween(db, uid, creatorUid)
    ) {
      throw new HttpsError(
        "permission-denied",
        "You cannot access this note.",
        {reason: "user_blocked"},
      );
    }
    const storedLockType = parseLockType(placeSnap.get("lockType"));
    if (storedLockType == null) {
      throw new HttpsError(
        "failed-precondition",
        "This note does not have a valid lock type.",
      );
    }
    const validation = validateLockSecret(password, storedLockType);
    if (validation) throw new HttpsError("invalid-argument", validation);

    const now = Date.now();
    const attemptSnap = await attemptRef.get();
    const inWindow =
      attemptSnap.exists &&
      now - (attemptSnap.get("firstAttemptAt") as Timestamp).toMillis() <
        ATTEMPT_WINDOW_MS;
    if (inWindow && (attemptSnap.get("count") as number) >= MAX_ATTEMPTS) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many attempts. Please try again later.",
      );
    }

    const authSnap = await placeRef.collection("secret").doc("auth").get();
    if (!authSnap.exists) {
      throw new HttpsError(
        "failed-precondition",
        "This note is not password-protected.",
      );
    }

    const ok = await verifyLockSecret(authSnap.get("hash") as string, password);

    if (!ok) {
      await attemptRef.set(
        inWindow ?
          {count: FieldValue.increment(1)} :
          {count: 1, firstAttemptAt: FieldValue.serverTimestamp()},
        {merge: true},
      );
      throw new HttpsError("permission-denied", "Incorrect password.");
    }

    const profile = await profileForMember(
      uid,
      req.auth?.token.name,
    );

    const batch = db.batch();
    batch.set(
      placeRef.collection("members").doc(uid),
      {
        userId: uid,
        viaPasswordVersion: authSnap.get("passwordVersion") as number,
        grantedAt: FieldValue.serverTimestamp(),
        displayName: profile.displayName,
      },
      {merge: true},
    );
    batch.delete(attemptRef);
    await batch.commit();

    return {ok: true};
  },
);
