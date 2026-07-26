import {
  DocumentReference,
  Firestore,
  Transaction,
} from "firebase-admin/firestore";

/**
 * Returns the private block document for one directed user relationship.
 *
 * The document path identifies both users, so the document needs only its
 * creation timestamp.
 *
 * @param {Firestore} db Firestore instance.
 * @param {string} blockerUid User who created the block.
 * @param {string} blockedUid User who was blocked.
 * @return {DocumentReference} Directed block document.
 */
export function userBlockRef(
  db: Firestore,
  blockerUid: string,
  blockedUid: string,
): DocumentReference {
  return db
    .collection("users")
    .doc(blockerUid)
    .collection("blockedUsers")
    .doc(blockedUid);
}

/**
 * Checks whether either user has blocked the other.
 *
 * @param {Firestore} db Firestore instance.
 * @param {string} firstUid First user.
 * @param {string} secondUid Second user.
 * @return {Promise<boolean>} Whether a block exists in either direction.
 */
export async function hasUserBlockBetween(
  db: Firestore,
  firstUid: string,
  secondUid: string,
): Promise<boolean> {
  if (firstUid === secondUid) return false;
  const [firstToSecond, secondToFirst] = await Promise.all([
    userBlockRef(db, firstUid, secondUid).get(),
    userBlockRef(db, secondUid, firstUid).get(),
  ]);
  return firstToSecond.exists || secondToFirst.exists;
}

/**
 * Transactional variant used when the caller will mutate a related edge.
 *
 * Reading both block documents makes a concurrent block/follow race retry
 * against the block transaction instead of leaving contradictory state.
 *
 * @param {Transaction} tx Active Firestore transaction.
 * @param {Firestore} db Firestore instance.
 * @param {string} firstUid First user.
 * @param {string} secondUid Second user.
 * @return {Promise<boolean>} Whether a block exists in either direction.
 */
export async function hasUserBlockBetweenInTransaction(
  tx: Transaction,
  db: Firestore,
  firstUid: string,
  secondUid: string,
): Promise<boolean> {
  if (firstUid === secondUid) return false;
  const [firstToSecond, secondToFirst] = await Promise.all([
    tx.get(userBlockRef(db, firstUid, secondUid)),
    tx.get(userBlockRef(db, secondUid, firstUid)),
  ]);
  return firstToSecond.exists || secondToFirst.exists;
}
