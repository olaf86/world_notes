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
 * Finds candidate user ids blocked in either direction with the viewer.
 *
 * listMapPins passes the distinct creator ids from its bounded geographic
 * result, then removes every pin whose creator is returned here. For each
 * candidate this checks both directed documents:
 *
 * - viewer -> candidate: the viewer blocked the candidate
 * - candidate -> viewer: the candidate blocked the viewer
 *
 * The incoming direction cannot be discovered from the viewer's private
 * blockedUsers collection, so both exact paths are read together with getAll.
 *
 * @param {Firestore} db Firestore instance.
 * @param {string} viewerUid Signed-in viewer.
 * @param {string[]} candidateUids Bounded user ids to check.
 * @return {Promise<Set<string>>} Ids with a block in either direction.
 */
export async function findUserIdsWithBlockRelationshipToViewer(
  db: Firestore,
  viewerUid: string,
  candidateUids: string[],
): Promise<Set<string>> {
  const candidates = [...new Set(candidateUids)]
    .filter((uid) => uid.length > 0 && uid !== viewerUid);
  if (candidates.length === 0) return new Set();

  const refs = candidates.flatMap((candidateUid) => [
    userBlockRef(db, viewerUid, candidateUid),
    userBlockRef(db, candidateUid, viewerUid),
  ]);
  const snapshots = await db.getAll(...refs);
  const blocked = new Set<string>();
  for (let index = 0; index < candidates.length; index++) {
    if (snapshots[index * 2].exists || snapshots[index * 2 + 1].exists) {
      blocked.add(candidates[index]);
    }
  }
  return blocked;
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
