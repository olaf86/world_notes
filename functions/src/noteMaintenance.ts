import {DocumentSnapshot} from "firebase-admin/firestore";

/**
 * Reads maintainerIds, falling back to ownerIds during migration.
 *
 * @param {DocumentSnapshot} placeSnap The note document.
 * @return {string[]} Creator plus delegated maintainer ids.
 */
export function maintainerIdsOf(placeSnap: DocumentSnapshot): string[] {
  const maintainerIds =
    placeSnap.get("maintainerIds") as string[] | undefined;
  if (maintainerIds != null) return maintainerIds;

  const legacyOwnerIds = placeSnap.get("ownerIds") as string[] | undefined;
  return legacyOwnerIds ?? [];
}

/**
 * Returns whether uid is the original creator of the note.
 *
 * @param {DocumentSnapshot} placeSnap The note document.
 * @param {string} uid The user id to check.
 * @return {boolean} Whether the user created the note.
 */
export function isNoteCreator(
  placeSnap: DocumentSnapshot,
  uid: string,
): boolean {
  return placeSnap.get("createdByUserId") === uid;
}

/**
 * Returns whether uid has maintainer-level access.
 *
 * @param {DocumentSnapshot} placeSnap The note document.
 * @param {string} uid The user id to check.
 * @return {boolean} Whether the user can maintain the note.
 */
export function isNoteMaintainer(
  placeSnap: DocumentSnapshot,
  uid: string,
): boolean {
  return isNoteCreator(placeSnap, uid) ||
    maintainerIdsOf(placeSnap).includes(uid);
}
