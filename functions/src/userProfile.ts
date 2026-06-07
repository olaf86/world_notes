import {getFirestore} from "firebase-admin/firestore";

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
    stringOrNull(data?.name) ??
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
