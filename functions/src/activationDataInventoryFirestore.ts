/* eslint-disable require-jsdoc, valid-jsdoc */

import {
  type Firestore,
  type Query,
} from "firebase-admin/firestore";

import type {WorldActivationDataCounts} from "./activationDataInventory";

async function count(query: Query): Promise<number> {
  return (await query.count().get()).data().count;
}

/** Collects the content-free activation counts for one trusted database. */
export async function collectWorldActivationData(
  worldId: string,
  firestore: Firestore,
): Promise<WorldActivationDataCounts> {
  const [
    userHomes,
    privateUsers,
    publicProfiles,
    userEntitlements,
    userUsage,
    accountSafety,
    socialEdges,
    blockedUsers,
    places,
    pendingGlobalOperations,
    failedGlobalOperations,
  ] = await Promise.all([
    count(firestore.collection("userHomes")),
    count(firestore.collection("users")),
    count(firestore.collection("publicProfiles")),
    count(firestore.collection("userEntitlements")),
    count(firestore.collection("userUsage")),
    count(firestore.collection("accountSafety")),
    count(firestore.collection("socialEdges")),
    count(firestore.collectionGroup("blockedUsers")),
    count(firestore.collection("places")),
    count(firestore.collection("globalOperations")
      .where("status", "==", "pending")),
    count(firestore.collection("globalOperations")
      .where("status", "==", "failed")),
  ]);
  return Object.freeze({
    worldId,
    userHomes,
    privateUsers,
    publicProfiles,
    userEntitlements,
    userUsage,
    accountSafety,
    socialEdges,
    blockedUsers,
    places,
    pendingGlobalOperations,
    failedGlobalOperations,
  });
}
