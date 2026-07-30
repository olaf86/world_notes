import assert from "node:assert/strict";
import {randomUUID} from "node:crypto";
import test from "node:test";

import {deleteApp, initializeApp} from "firebase-admin/app";
import {
  DocumentReference,
  FieldValue,
} from "firebase-admin/firestore";

import {
  DEFAULT_FIRESTORE_DATABASE_ID,
  WorldFirestoreProvider,
} from "../src/platform/worldFirestoreProvider";

const hasFirestoreEmulator = process.env.FIRESTORE_EMULATOR_HOST !== undefined;
const cloudProjectId = process.env.P00_FIRESTORE_PROJECT_ID;
const confirmedCloudProjectId = process.env.P00_CONFIRM_PROJECT_ID;
const shouldRunContract =
  hasFirestoreEmulator || cloudProjectId !== undefined;

test(
  "named Firestore databases satisfy the P00 server contract",
  {skip: !shouldRunContract},
  async () => {
    if (!hasFirestoreEmulator &&
        confirmedCloudProjectId !== cloudProjectId) {
      throw new Error(
        "Cloud contract requires matching P00_FIRESTORE_PROJECT_ID and " +
        "P00_CONFIRM_PROJECT_ID values.",
      );
    }

    const runId = randomUUID();
    const projectId = hasFirestoreEmulator ?
      "demo-world-notes-p00" :
      cloudProjectId as string;
    const app = initializeApp(
      {projectId},
      `p00-${runId}`,
    );
    const provider = new WorldFirestoreProvider(
      [
        {worldId: "asia", databaseId: DEFAULT_FIRESTORE_DATABASE_ID},
        {worldId: "northAmerica", databaseId: "north-america"},
        {worldId: "europe", databaseId: "europe"},
      ],
      {appProvider: () => app},
    );
    const asia = provider.forWorld("asia");
    const northAmerica = provider.forWorld("northAmerica");
    const europe = provider.forWorld("europe");
    const cleanupRefs: DocumentReference[] = [];

    try {
      assert.equal(asia.databaseId, "(default)");
      assert.equal(northAmerica.databaseId, "north-america");
      assert.equal(europe.databaseId, "europe");

      const isolationPath = `__p00_contracts/${runId}`;
      cleanupRefs.push(
        asia.doc(isolationPath),
        northAmerica.doc(isolationPath),
        europe.doc(isolationPath),
      );
      await Promise.all([
        asia.doc(isolationPath).set({world: "asia"}),
        northAmerica.doc(isolationPath).set({world: "northAmerica"}),
        europe.doc(isolationPath).set({world: "europe", count: 0}),
      ]);
      const isolationSnapshots = await Promise.all([
        asia.doc(isolationPath).get(),
        northAmerica.doc(isolationPath).get(),
        europe.doc(isolationPath).get(),
      ]);
      assert.deepEqual(
        isolationSnapshots.map((snapshot) => snapshot.get("world")),
        ["asia", "northAmerica", "europe"],
      );

      await europe.runTransaction(async (transaction) => {
        const ref = europe.doc(isolationPath);
        const snapshot = await transaction.get(ref);
        transaction.update(ref, {
          count: (snapshot.get("count") as number) + 1,
        });
      });
      assert.equal(
        (await europe.doc(isolationPath).get()).get("count"),
        1,
      );

      const batch = northAmerica.batch();
      const firstItemRef = northAmerica.doc(
        `__p00_contract_parents/${runId}/messageLikes/first`,
      );
      const secondItemRef = northAmerica.doc(
        `__p00_contract_others/${runId}/messageLikes/second`,
      );
      cleanupRefs.push(firstItemRef, secondItemRef);
      batch.set(
        firstItemRef,
        {
          placeId: runId,
          userId: "p00-contract",
          liked: true,
          order: 1,
        },
      );
      batch.set(
        secondItemRef,
        {
          placeId: runId,
          userId: "p00-contract",
          liked: true,
          order: 2,
        },
      );
      await batch.commit();
      const itemSnapshots = await northAmerica
        .collectionGroup("messageLikes")
        .where("placeId", "==", runId)
        .where("userId", "==", "p00-contract")
        .where("liked", "==", true)
        .get();
      assert.deepEqual(
        itemSnapshots.docs
          .map((snapshot) => snapshot.get("order") as number)
          .sort(),
        [1, 2],
      );

      const sourceRef = asia.doc(`__p00_replication/${runId}`);
      const replicaRef = europe.doc(`__p00_replication/${runId}`);
      cleanupRefs.push(sourceRef, replicaRef);
      await sourceRef.set({
        value: "from-asia",
        revision: 1,
        createdAt: FieldValue.serverTimestamp(),
      });
      const source = await sourceRef.get();
      await replicaRef.set({
        ...source.data(),
        replicatedFrom: asia.databaseId,
      });
      const replica = await replicaRef.get();
      assert.equal(replica.get("value"), "from-asia");
      assert.equal(replica.get("revision"), 1);
      assert.equal(replica.get("replicatedFrom"), "(default)");
    } finally {
      await Promise.allSettled(cleanupRefs.map((ref) => ref.delete()));
      await Promise.all([
        asia.terminate(),
        northAmerica.terminate(),
        europe.terminate(),
      ]);
      await deleteApp(app);
    }
  },
);
