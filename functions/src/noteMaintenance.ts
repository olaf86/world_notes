import {DocumentSnapshot, Timestamp} from "firebase-admin/firestore";

/**
 * Returns whether a note exists and remains administratively active.
 *
 * @param {DocumentSnapshot} placeSnap The note document.
 * @param {number} nowMillis Current server time in milliseconds.
 * @return {boolean} Whether administrative actions may use this note.
 */
export function isActiveNoteForAdministration(
  placeSnap: DocumentSnapshot,
  nowMillis: number,
): boolean {
  const expiresAt = placeSnap.get("expiresAt");
  return placeSnap.exists &&
    placeSnap.get("isArchived") !== true &&
    placeSnap.get("isModerationHidden") === false &&
    expiresAt instanceof Timestamp &&
    expiresAt.toMillis() > nowMillis;
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
 * @param {DocumentSnapshot|null} administratorSnap The delegated relationship.
 * @param {string} uid The user id to check.
 * @return {boolean} Whether the user can maintain the note.
 */
export function isNoteMaintainer(
  placeSnap: DocumentSnapshot,
  administratorSnap: DocumentSnapshot | null,
  uid: string,
): boolean {
  return isNoteCreator(placeSnap, uid) ||
    (administratorSnap?.exists === true &&
      administratorSnap.id === uid &&
      administratorSnap.get("userId") === uid);
}

/**
 * Returns whether uid may perform maintainer-level actions.
 *
 * @param {DocumentSnapshot} placeSnap The note document.
 * @param {DocumentSnapshot|null} administratorSnap The delegated relationship.
 * @param {string} uid The user id to check.
 * @return {boolean} Whether the user can maintain the note.
 */
export function canMaintainNote(
  placeSnap: DocumentSnapshot,
  administratorSnap: DocumentSnapshot | null,
  uid: string,
): boolean {
  return isNoteMaintainer(placeSnap, administratorSnap, uid);
}

/**
 * Returns whether uid may set or change the note lock.
 *
 * @param {DocumentSnapshot} placeSnap The note document.
 * @param {string} uid The user id to check.
 * @return {boolean} Whether the user can change the lock.
 */
export function canChangeNoteLock(
  placeSnap: DocumentSnapshot,
  uid: string,
): boolean {
  return isNoteCreator(placeSnap, uid);
}
