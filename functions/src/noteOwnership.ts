import {DocumentSnapshot} from "firebase-admin/firestore";

/**
 * Reads ownerIds from notes that may have been created before that field.
 *
 * @param {DocumentSnapshot} placeSnap The note document.
 * @return {string[]} Owner ids stored on the note.
 */
export function ownerIdsOf(placeSnap: DocumentSnapshot): string[] {
  const ownerIds = placeSnap.get("ownerIds") as string[] | undefined;
  return ownerIds ?? [];
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
 * Returns whether uid is the creator or a co-owner of the note.
 *
 * @param {DocumentSnapshot} placeSnap The note document.
 * @param {string} uid The user id to check.
 * @return {boolean} Whether the user owns the note.
 */
export function isNoteOwner(
  placeSnap: DocumentSnapshot,
  uid: string,
): boolean {
  return isNoteCreator(placeSnap, uid) || ownerIdsOf(placeSnap).includes(uid);
}
