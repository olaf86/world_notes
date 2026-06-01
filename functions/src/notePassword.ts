import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {
  getFirestore,
  FieldValue,
  Timestamp,
} from "firebase-admin/firestore";
import * as argon2 from "argon2";

import {REGION} from "./constants";

// Server-only secret (pepper). Stored in Secret Manager, never in the repo.
// Set with: firebase functions:secrets:set NOTE_PW_PEPPER
const PEPPER = defineSecret("NOTE_PW_PEPPER");

// argon2id parameters — OWASP minimum baseline.
const ARGON2_OPTS = {
  type: argon2.argon2id,
  memoryCost: 19456, // 19 MiB
  timeCost: 2,
  parallelism: 1,
} as const;

// Online brute-force protection for unlockNote.
const MAX_ATTEMPTS = 5;
const ATTEMPT_WINDOW_MS = 15 * 60 * 1000; // 15 minutes

/**
 * Server-side password strength check (mirror of PasswordUtil.validate).
 *
 * @param {string} pw The candidate password.
 * @return {string | null} An error message, or null if the password is valid.
 */
function validatePassword(pw: string): string | null {
  if (pw.length < 8) return "Password must be at least 8 characters.";
  if (!/[A-Z]/.test(pw)) return "Password needs an uppercase letter.";
  if (!/[a-z]/.test(pw)) return "Password needs a lowercase letter.";
  if (!/[0-9]/.test(pw)) return "Password needs a digit.";
  if (!/[^A-Za-z0-9]/.test(pw)) return "Password needs a special character.";
  return null;
}

/**
 * Owner-only: set or change a note's password (locks it as private).
 *
 * The hash lives in places/{id}/secret/auth, which clients can never read,
 * and is keyed by a server pepper so a Firestore leak alone can't crack it.
 * Bumping passwordVersion invalidates every remembered unlock from the old
 * password (members carry the version they unlocked with).
 */
export const setNotePassword = onCall<{placeId?: unknown; password?: unknown}>(
  {secrets: [PEPPER], enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const {placeId, password} = req.data ?? {};
    if (typeof placeId !== "string" || placeId.length === 0) {
      throw new HttpsError("invalid-argument", "placeId is required.");
    }
    if (typeof password !== "string") {
      throw new HttpsError("invalid-argument", "password is required.");
    }
    const weakness = validatePassword(password);
    if (weakness) throw new HttpsError("invalid-argument", weakness);

    const db = getFirestore();
    const placeRef = db.collection("places").doc(placeId);
    const placeSnap = await placeRef.get();
    if (!placeSnap.exists) {
      throw new HttpsError("not-found", "Note not found.");
    }
    if (placeSnap.get("createdByUserId") !== uid) {
      throw new HttpsError("permission-denied", "Only the owner can do this.");
    }

    const newVersion = ((placeSnap.get("passwordVersion") as number) ?? 0) + 1;
    const hash = await argon2.hash(password, {
      ...ARGON2_OPTS,
      secret: Buffer.from(PEPPER.value()),
    });

    const batch = db.batch();
    batch.set(placeRef.collection("secret").doc("auth"), {
      hash,
      passwordVersion: newVersion,
    });
    batch.update(placeRef, {
      visibility: "private",
      passwordVersion: newVersion,
    });
    await batch.commit();

    return {ok: true, passwordVersion: newVersion};
  },
);

/**
 * Verify a password and, on success, grant the caller remembered access.
 *
 * Rate-limited per user+note to blunt online brute force. On success a
 * members/{uid} doc records the passwordVersion unlocked with, so the user
 * is not prompted again until the owner changes the password.
 */
export const unlockNote = onCall<{placeId?: unknown; password?: unknown}>(
  {secrets: [PEPPER], enforceAppCheck: true, region: REGION},
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

    const db = getFirestore();
    const placeRef = db.collection("places").doc(placeId);
    const attemptRef = placeRef.collection("attempts").doc(uid);

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

    const ok = await argon2.verify(
      authSnap.get("hash") as string,
      password,
      {secret: Buffer.from(PEPPER.value())},
    );

    if (!ok) {
      await attemptRef.set(
        inWindow ?
          {count: FieldValue.increment(1)} :
          {count: 1, firstAttemptAt: FieldValue.serverTimestamp()},
        {merge: true},
      );
      throw new HttpsError("permission-denied", "Incorrect password.");
    }

    const batch = db.batch();
    batch.set(placeRef.collection("members").doc(uid), {
      viaPasswordVersion: authSnap.get("passwordVersion") as number,
      grantedAt: FieldValue.serverTimestamp(),
    });
    batch.delete(attemptRef);
    await batch.commit();

    return {ok: true};
  },
);
