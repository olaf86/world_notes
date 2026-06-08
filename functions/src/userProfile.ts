import {getAuth} from "firebase-admin/auth";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";

import {REGION} from "./constants";

const MAX_DISPLAY_NAME_LENGTH = 20;

/**
 * Returns the app profile fields shown in a note's member list.
 *
 * @param {string} uid The signed-in user's uid.
 * @param {string | undefined} tokenName Display name from the auth token.
 * @param {string | undefined} tokenEmail Email from the auth token.
 * @return {Promise<object>} User-facing profile fields.
 */
export async function profileForMember(
  uid: string,
  tokenName?: string,
  tokenEmail?: string,
): Promise<{displayName: string | null; email: string | null}> {
  const snap = await getFirestore().collection("users").doc(uid).get();
  const data = snap.data();
  const displayName = stringOrNull(data?.displayName) ??
    stringOrNull(tokenName);
  const email = stringOrNull(data?.email) ?? stringOrNull(tokenEmail);
  return {displayName, email};
}

/**
 * Coerces non-empty strings to a display-safe value.
 *
 * @param {unknown} value The value to inspect.
 * @return {string | null} The trimmed string, or null.
 */
function stringOrNull(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/**
 * Updates the caller's nickname and refreshes access-list display names.
 */
export const updateDisplayName = onCall<{displayName?: unknown}>(
  {enforceAppCheck: true, region: REGION},
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const rawDisplayName = req.data?.displayName;
    if (typeof rawDisplayName !== "string") {
      throw new HttpsError("invalid-argument", "displayName is required.");
    }

    const displayName = rawDisplayName.trim();
    if (
      displayName.length === 0 ||
      displayName.length > MAX_DISPLAY_NAME_LENGTH
    ) {
      throw new HttpsError(
        "invalid-argument",
        `Nickname must be 1-${MAX_DISPLAY_NAME_LENGTH} characters.`,
      );
    }

    const db = getFirestore();
    await Promise.all([
      db.collection("users").doc(uid).set(
        {
          displayName,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      ),
      getAuth().updateUser(uid, {displayName}),
    ]);

    const members = await db
      .collectionGroup("members")
      .where("userId", "==", uid)
      .get();

    for (let i = 0; i < members.docs.length; i += 450) {
      const batch = db.batch();
      for (const doc of members.docs.slice(i, i + 450)) {
        batch.update(doc.ref, {userId: uid, displayName});
      }
      await batch.commit();
    }

    return {
      displayName,
      updatedMemberCount: members.size,
    };
  },
);
