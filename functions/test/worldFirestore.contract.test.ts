import assert from "node:assert/strict";
import {randomUUID} from "node:crypto";
import {after, before, test} from "node:test";

import {App, deleteApp, initializeApp} from "firebase-admin/app";
import {
  DocumentReference,
  FieldValue,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";

import {
  GlobalReplicationHandler,
  GlobalReplicationHandlerRegistry,
  processGlobalOperation,
} from "../src/globalReplication";
import {WORLD_CATALOG} from "../src/platform/worldCatalog";
import {
  DEFAULT_FIRESTORE_DATABASE_ID,
  WorldFirestoreProvider,
} from "../src/platform/worldFirestoreProvider";

const hasFirestoreEmulator = process.env.FIRESTORE_EMULATOR_HOST !== undefined;
const cloudProjectId = process.env.FIRESTORE_CONTRACT_PROJECT_ID;
const confirmedCloudProjectId =
  process.env.FIRESTORE_CONTRACT_CONFIRM_PROJECT_ID;
const shouldRunContract =
  hasFirestoreEmulator || cloudProjectId !== undefined;

interface FirestoreContractContext {
  readonly runId: string;
  readonly app: App;
  readonly provider: WorldFirestoreProvider;
  readonly asia: Firestore;
  readonly northAmerica: Firestore;
  readonly europe: Firestore;
  readonly cleanupRefs: DocumentReference[];
}

let context: FirestoreContractContext | undefined;

before(() => {
  if (!shouldRunContract) {
    return;
  }
  if (!hasFirestoreEmulator &&
      confirmedCloudProjectId !== cloudProjectId) {
    throw new Error(
      "Cloud contract requires matching FIRESTORE_CONTRACT_PROJECT_ID and " +
      "FIRESTORE_CONTRACT_CONFIRM_PROJECT_ID values.",
    );
  }

  const runId = randomUUID();
  const projectId = hasFirestoreEmulator ?
    "demo-world-notes-firestore-contract" :
    cloudProjectId as string;
  const app = initializeApp(
    {projectId},
    `firestore-contract-${runId}`,
  );
  const provider = new WorldFirestoreProvider(
    [
      {worldId: "asia", databaseId: DEFAULT_FIRESTORE_DATABASE_ID},
      {worldId: "northAmerica", databaseId: "north-america"},
      {worldId: "europe", databaseId: "europe"},
    ],
    {appProvider: () => app},
  );

  context = {
    runId,
    app,
    provider,
    asia: provider.forWorld("asia"),
    northAmerica: provider.forWorld("northAmerica"),
    europe: provider.forWorld("europe"),
    cleanupRefs: [],
  };
});

after(async () => {
  if (context === undefined) {
    return;
  }

  const deletionResults = await Promise.allSettled(
    context.cleanupRefs.map((ref) => ref.delete()),
  );
  try {
    await Promise.all([
      context.asia.terminate(),
      context.northAmerica.terminate(),
      context.europe.terminate(),
    ]);
  } finally {
    await deleteApp(context.app);
  }

  const deletionFailures = deletionResults.filter(
    (result) => result.status === "rejected",
  );
  assert.equal(
    deletionFailures.length,
    0,
    "Firestore contract cleanup must delete every temporary document.",
  );
});

firestoreContractTest(
  "routes each world to its configured Firestore database",
  async () => {
    const {asia, northAmerica, europe} = requireContext();

    assert.equal(asia.databaseId, "(default)");
    assert.equal(northAmerica.databaseId, "north-america");
    assert.equal(europe.databaseId, "europe");
  },
);

firestoreContractTest(
  "isolates the same document path between world databases",
  async () => {
    const {runId, asia, northAmerica, europe} = requireContext();
    const isolationPath = `__firestore_contract_isolation/${runId}`;
    const asiaRef = asia.doc(isolationPath);
    const northAmericaRef = northAmerica.doc(isolationPath);
    const europeRef = europe.doc(isolationPath);
    trackForCleanup(asiaRef, northAmericaRef, europeRef);

    await Promise.all([
      asiaRef.set({world: "asia"}),
      northAmericaRef.set({world: "northAmerica"}),
      europeRef.set({world: "europe"}),
    ]);
    const snapshots = await Promise.all([
      asiaRef.get(),
      northAmericaRef.get(),
      europeRef.get(),
    ]);

    assert.deepEqual(
      snapshots.map((snapshot) => snapshot.get("world")),
      ["asia", "northAmerica", "europe"],
    );
  },
);

firestoreContractTest(
  "runs a transaction inside a named world database",
  async () => {
    const {runId, europe} = requireContext();
    const counterRef = europe.doc(
      `__firestore_contract_transactions/${runId}`,
    );
    trackForCleanup(counterRef);
    await counterRef.set({count: 0});

    await europe.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(counterRef);
      transaction.update(counterRef, {
        count: (snapshot.get("count") as number) + 1,
      });
    });

    assert.equal((await counterRef.get()).get("count"), 1);
  },
);

firestoreContractTest(
  "queries a batch through a production collection-group index",
  async () => {
    const {runId, northAmerica} = requireContext();
    const firstLikeRef = northAmerica.doc(
      `__firestore_contract_parents/${runId}/messageLikes/first`,
    );
    const secondLikeRef = northAmerica.doc(
      `__firestore_contract_others/${runId}/messageLikes/second`,
    );
    trackForCleanup(firstLikeRef, secondLikeRef);

    const batch = northAmerica.batch();
    batch.set(firstLikeRef, {
      placeId: runId,
      userId: "firestore-contract",
      liked: true,
      order: 1,
    });
    batch.set(secondLikeRef, {
      placeId: runId,
      userId: "firestore-contract",
      liked: true,
      order: 2,
    });
    await batch.commit();

    const snapshots = await northAmerica
      .collectionGroup("messageLikes")
      .where("placeId", "==", runId)
      .where("userId", "==", "firestore-contract")
      .where("liked", "==", true)
      .get();

    assert.deepEqual(
      snapshots.docs
        .map((snapshot) => snapshot.get("order") as number)
        .sort(),
      [1, 2],
    );
  },
);

firestoreContractTest(
  "copies a revision explicitly between world databases",
  async () => {
    const {runId, asia, europe} = requireContext();
    const sourceRef = asia.doc(`__firestore_contract_replication/${runId}`);
    const replicaRef = europe.doc(`__firestore_contract_replication/${runId}`);
    trackForCleanup(sourceRef, replicaRef);

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
  },
);

firestoreContractTest(
  "replicates and acknowledges one durable global operation",
  async () => {
    const {runId, asia, europe, provider} = requireContext();
    const operationId = testOperationId(runId);
    const entityPath = `__firestore_contract_global_entities/${runId}`;
    const sourceRef = asia.doc(entityPath);
    const replicaRef = europe.doc(entityPath);
    const operationRef = asia.collection("globalOperations").doc(operationId);
    trackForCleanup(sourceRef, replicaRef, operationRef);

    const acceptedAt = Timestamp.now();
    await sourceRef.set({value: "authority", revision: 1});
    await operationRef.set({
      operationId,
      operationType: "replicateContractEntity",
      entityId: runId,
      revision: 1,
      authorityWorld: "asia",
      ownerUid: "firestore-contract",
      payloadHash: "a".repeat(64),
      status: "pending",
      acceptedAt,
      worldCatalogVersion: 1,
      requiredWorlds: ["asia", "europe"],
      worldAcks: {
        asia: {revision: 1, acknowledgedAt: acceptedAt},
      },
      createdAt: acceptedAt,
      updatedAt: acceptedAt,
    });

    const handler: GlobalReplicationHandler = {
      operationType: "replicateContractEntity",
      apply: async ({authorityFirestore, destinationFirestore}) => {
        const authority = await authorityFirestore.doc(entityPath).get();
        const revision = authority.get("revision") as number;
        await destinationFirestore.runTransaction(async (transaction) => {
          const current = await transaction.get(
            destinationFirestore.doc(entityPath),
          );
          const currentRevision = current.exists ?
            current.get("revision") as number :
            0;
          if (currentRevision >= revision) return;
          transaction.set(destinationFirestore.doc(entityPath), {
            ...authority.data(),
            replicatedFrom: authorityFirestore.databaseId,
          });
        });
        return revision;
      },
    };
    const runtime = {
      catalog: WORLD_CATALOG,
      firestore: provider,
      handlers: new GlobalReplicationHandlerRegistry([handler]),
    };

    const first = await processGlobalOperation(
      "asia",
      operationId,
      runtime,
    );
    const replay = await processGlobalOperation(
      "asia",
      operationId,
      runtime,
    );
    const [replica, operation] = await Promise.all([
      replicaRef.get(),
      operationRef.get(),
    ]);

    assert.equal(first?.status, "complete");
    assert.equal(replay?.status, "complete");
    assert.equal(replica.get("value"), "authority");
    assert.equal(replica.get("revision"), 1);
    assert.equal(operation.get("status"), "complete");
    assert.equal(operation.get("worldAcks.europe.revision"), 1);
    assert.notEqual(operation.get("completedAt"), undefined);
    assert.notEqual(operation.get("expireAt"), undefined);
  },
);

/**
 * Registers a contract case that is skipped outside emulator/cloud runs.
 *
 * @param {string} name Human-readable contract behavior.
 * @param {function(): Promise<void>} run Contract case.
 */
function firestoreContractTest(
  name: string,
  run: () => Promise<void>,
): void {
  test(name, {skip: !shouldRunContract}, run);
}

/**
 * Returns the shared clients initialized by the suite hook.
 *
 * @return {FirestoreContractContext} Initialized contract context.
 */
function requireContext(): FirestoreContractContext {
  assert.ok(context, "Firestore contract context must be initialized.");
  return context;
}

/**
 * Registers temporary documents for cleanup after the complete contract run.
 *
 * @param {DocumentReference[]} refs Temporary document references.
 */
function trackForCleanup(...refs: DocumentReference[]): void {
  requireContext().cleanupRefs.push(...refs);
}

/**
 * Creates an obvious, run-scoped UUID v7 fixture.
 *
 * @param {string} runId Unique contract run identifier.
 * @return {string} Valid deterministic UUID v7 test fixture.
 */
function testOperationId(runId: string): string {
  const suffix = runId.replace(/-/g, "").slice(0, 12);
  return `00000000-0000-700a-800b-${suffix}`;
}
