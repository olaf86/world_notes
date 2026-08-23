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
import {syncProfileSnapshots} from "../src/creatorProfileSnapshots";
import {
  cleanupJobId,
  CleanupJobHandler,
  CleanupJobHandlerRegistry,
  newCleanupJobData,
  processCleanupJob,
} from "../src/cleanupJobs";
import {
  accountDeletionFirestoreHandler,
  accountDeletionId,
  DELETE_ACCOUNT_DATA_JOB,
} from "../src/accountDeletion";
import {
  ModerationJobHandler,
  ModerationJobHandlerRegistry,
  moderationJobId,
  newModerationJobData,
  processModerationJob,
} from "../src/moderationJobs";
import {
  publicProfileReplicationHandler,
  SET_USER_ENTITLEMENT_OPERATION,
  UPDATE_PUBLIC_PROFILE_OPERATION,
  userEntitlementReplicationHandler,
} from "../src/profileEntitlementReplication";
import {
  SET_USER_FOLLOW_OPERATION,
  socialEdgeId,
  socialEdgeReplicationHandler,
} from "../src/socialEdgeReplication";
import {
  BLOCK_RELATIONSHIP_CLEANUP_JOB,
  BLOCK_TOMBSTONE_RETENTION_MILLIS,
  SET_USER_BLOCK_OPERATION,
  userBlockEntityId,
  userBlockReplicationHandler,
} from "../src/userBlockReplication";
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
  "queries a batch through a production composite index",
  async () => {
    const {runId, northAmerica} = requireContext();
    const firstJobRef = northAmerica.doc(
      `__firestore_contract_parents/${runId}/jobs/first`,
    );
    const secondJobRef = northAmerica.doc(
      `__firestore_contract_parents/${runId}/jobs/second`,
    );
    trackForCleanup(firstJobRef, secondJobRef);

    const batch = northAmerica.batch();
    batch.set(firstJobRef, {
      status: "pending",
      nextAttemptAt: Timestamp.fromMillis(1),
      order: 1,
    });
    batch.set(secondJobRef, {
      status: "pending",
      nextAttemptAt: Timestamp.fromMillis(2),
      order: 2,
    });
    await batch.commit();

    const snapshots = await northAmerica
      .collection(`__firestore_contract_parents/${runId}/jobs`)
      .where("status", "==", "pending")
      .orderBy("nextAttemptAt")
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

firestoreContractTest(
  "replicates public identity without replacing destination social counts",
  async () => {
    const {runId, asia, europe, provider} = requireContext();
    const uid = `profile-${runId}`;
    const operationId = testOperationId(runId, "00c");
    const sourceRef = asia.collection("publicProfiles").doc(uid);
    const destinationRef = europe.collection("publicProfiles").doc(uid);
    const operationRef = asia.collection("globalOperations").doc(operationId);
    trackForCleanup(sourceRef, destinationRef, operationRef);
    const now = Timestamp.now();
    await Promise.all([
      sourceRef.set({
        displayName: "Authority",
        photoUrl: null,
        photoVersion: 2,
        revision: 2,
        followerCount: 4,
        followingCount: 5,
        createdAt: now,
        updatedAt: now,
      }),
      destinationRef.set({
        displayName: "Old",
        photoUrl: null,
        photoVersion: 1,
        revision: 1,
        followerCount: 99,
        followingCount: 88,
        createdAt: now,
        updatedAt: now,
      }),
      operationRef.set(pendingOperationData({
        operationId,
        operationType: UPDATE_PUBLIC_PROFILE_OPERATION,
        entityId: uid,
        ownerUid: uid,
        revision: 2,
        acceptedAt: now,
      })),
    ]);

    await processGlobalOperation("asia", operationId, {
      catalog: WORLD_CATALOG,
      firestore: provider,
      handlers: new GlobalReplicationHandlerRegistry([
        publicProfileReplicationHandler,
      ]),
    });
    const [destination, operation] = await Promise.all([
      destinationRef.get(),
      operationRef.get(),
    ]);

    assert.equal(destination.get("displayName"), "Authority");
    assert.equal(destination.get("revision"), 2);
    assert.equal(destination.get("followerCount"), 99);
    assert.equal(destination.get("followingCount"), 88);
    assert.equal(operation.get("status"), "complete");
  },
);

firestoreContractTest(
  "replicates one entitlement projection into a named database",
  async () => {
    const {runId, asia, europe, provider} = requireContext();
    const uid = `entitlement-${runId}`;
    const operationId = testOperationId(runId, "00d");
    const sourceRef = asia.collection("userEntitlements").doc(uid);
    const destinationRef = europe.collection("userEntitlements").doc(uid);
    const operationRef = asia.collection("globalOperations").doc(operationId);
    trackForCleanup(sourceRef, destinationRef, operationRef);
    const now = Timestamp.now();
    await Promise.all([
      sourceRef.set({
        isPremium: true,
        revision: 3,
        sourceCheckedAt: now,
        updatedAt: now,
      }),
      operationRef.set(pendingOperationData({
        operationId,
        operationType: SET_USER_ENTITLEMENT_OPERATION,
        entityId: uid,
        ownerUid: uid,
        revision: 3,
        acceptedAt: now,
      })),
    ]);

    await processGlobalOperation("asia", operationId, {
      catalog: WORLD_CATALOG,
      firestore: provider,
      handlers: new GlobalReplicationHandlerRegistry([
        userEntitlementReplicationHandler,
      ]),
    });
    const [destination, operation] = await Promise.all([
      destinationRef.get(),
      operationRef.get(),
    ]);

    assert.equal(destination.get("isPremium"), true);
    assert.equal(destination.get("revision"), 3);
    assert.deepEqual(destination.get("sourceCheckedAt"), now);
    assert.equal(operation.get("status"), "complete");
  },
);

firestoreContractTest(
  "replicates social edge transitions with convergent profile counts",
  async () => {
    const {runId, asia, europe, provider} = requireContext();
    const followerUid = `follower-${runId}`;
    const followeeUid = `followee-${runId}`;
    const edgeId = socialEdgeId(followerUid, followeeUid);
    const sourceRef = asia.collection("socialEdges").doc(edgeId);
    const destinationRef = europe.collection("socialEdges").doc(edgeId);
    const followerProfileRef = europe
      .collection("publicProfiles")
      .doc(followerUid);
    const followeeProfileRef = europe
      .collection("publicProfiles")
      .doc(followeeUid);
    const createOperationId = testOperationId(runId, "00e");
    const deleteOperationId = testOperationId(runId, "00f");
    const createOperationRef = asia
      .collection("globalOperations")
      .doc(createOperationId);
    const deleteOperationRef = asia
      .collection("globalOperations")
      .doc(deleteOperationId);
    trackForCleanup(
      sourceRef,
      destinationRef,
      followerProfileRef,
      followeeProfileRef,
      createOperationRef,
      deleteOperationRef,
    );
    const createdAt = Timestamp.now();
    const profile = {
      displayName: "Contract User",
      photoUrl: null,
      photoVersion: 1,
      revision: 1,
      followerCount: 0,
      followingCount: 0,
      createdAt,
      updatedAt: createdAt,
    };
    await Promise.all([
      followerProfileRef.set(profile),
      followeeProfileRef.set(profile),
      sourceRef.set({
        followerUid,
        followeeUid,
        following: true,
        revision: 1,
        createdAt,
        updatedAt: createdAt,
      }),
      createOperationRef.set(pendingOperationData({
        operationId: createOperationId,
        operationType: SET_USER_FOLLOW_OPERATION,
        entityId: edgeId,
        ownerUid: followerUid,
        revision: 1,
        acceptedAt: createdAt,
      })),
    ]);
    const runtime = {
      catalog: WORLD_CATALOG,
      firestore: provider,
      handlers: new GlobalReplicationHandlerRegistry([
        socialEdgeReplicationHandler,
      ]),
    };

    await processGlobalOperation("asia", createOperationId, runtime);
    const [active, followerAfterCreate, followeeAfterCreate] =
      await Promise.all([
        destinationRef.get(),
        followerProfileRef.get(),
        followeeProfileRef.get(),
      ]);
    assert.equal(active.get("following"), true);
    assert.equal(followerAfterCreate.get("followingCount"), 1);
    assert.equal(followeeAfterCreate.get("followerCount"), 1);

    const removedAt = Timestamp.fromMillis(createdAt.toMillis() + 1);
    await Promise.all([
      sourceRef.set({
        followerUid,
        followeeUid,
        following: false,
        revision: 2,
        createdAt,
        updatedAt: removedAt,
      }),
      deleteOperationRef.set(pendingOperationData({
        operationId: deleteOperationId,
        operationType: SET_USER_FOLLOW_OPERATION,
        entityId: edgeId,
        ownerUid: followerUid,
        revision: 2,
        acceptedAt: removedAt,
      })),
    ]);
    await processGlobalOperation("asia", deleteOperationId, runtime);
    const [inactive, followerAfterDelete, followeeAfterDelete] =
      await Promise.all([
        destinationRef.get(),
        followerProfileRef.get(),
        followeeProfileRef.get(),
      ]);
    assert.equal(inactive.get("following"), false);
    assert.equal(inactive.get("revision"), 2);
    assert.equal(followerAfterDelete.get("followingCount"), 0);
    assert.equal(followeeAfterDelete.get("followerCount"), 0);
  },
);

firestoreContractTest(
  "applies block cleanup before ack and starts tombstone TTL at completion",
  async () => {
    const {runId, asia, europe, provider} = requireContext();
    const blockerUid = `blocker-${runId}`;
    const blockedUid = `blocked-${runId}`;
    const entityId = userBlockEntityId(blockerUid, blockedUid);
    const sourceRef = asia
      .collection("users")
      .doc(blockerUid)
      .collection("blockedUsers")
      .doc(blockedUid);
    const destinationRef = europe
      .collection("users")
      .doc(blockerUid)
      .collection("blockedUsers")
      .doc(blockedUid);
    const blockOperationId = testOperationId(runId, "010");
    const unblockOperationId = testOperationId(runId, "011");
    const blockOperationRef = asia
      .collection("globalOperations")
      .doc(blockOperationId);
    const unblockOperationRef = asia
      .collection("globalOperations")
      .doc(unblockOperationId);
    const cleanupInput = {
      sourceOperationId: blockOperationId,
      entityType: "userBlock",
      entityId,
      revision: 1,
      world: "europe",
      queue: "firestore" as const,
      jobType: BLOCK_RELATIONSHIP_CLEANUP_JOB,
    };
    const cleanupRef = europe.doc(
      `cleanupQueues/firestore/jobs/${cleanupJobId(cleanupInput)}`,
    );
    trackForCleanup(
      sourceRef,
      destinationRef,
      blockOperationRef,
      unblockOperationRef,
      cleanupRef,
    );
    const blockedAt = Timestamp.now();
    await Promise.all([
      sourceRef.set({
        blockedUid,
        isBlocked: true,
        revision: 1,
        authorityWorld: "asia",
        updatedAt: blockedAt,
        expireAt: null,
      }),
      blockOperationRef.set(pendingOperationData({
        operationId: blockOperationId,
        operationType: SET_USER_BLOCK_OPERATION,
        entityId,
        ownerUid: blockerUid,
        revision: 1,
        acceptedAt: blockedAt,
      })),
    ]);
    const runtime = {
      catalog: WORLD_CATALOG,
      firestore: provider,
      handlers: new GlobalReplicationHandlerRegistry([
        userBlockReplicationHandler,
      ]),
    };

    await processGlobalOperation("asia", blockOperationId, runtime);
    const [active, cleanup] = await Promise.all([
      destinationRef.get(),
      cleanupRef.get(),
    ]);
    assert.equal(active.get("isBlocked"), true);
    assert.equal(active.get("expireAt"), null);
    assert.equal(cleanup.get("status"), "pending");

    const unblockedAt = Timestamp.fromMillis(blockedAt.toMillis() + 1);
    await Promise.all([
      sourceRef.set({
        blockedUid,
        isBlocked: false,
        revision: 2,
        authorityWorld: "asia",
        updatedAt: unblockedAt,
        expireAt: null,
      }),
      unblockOperationRef.set(pendingOperationData({
        operationId: unblockOperationId,
        operationType: SET_USER_BLOCK_OPERATION,
        entityId,
        ownerUid: blockerUid,
        revision: 2,
        acceptedAt: unblockedAt,
      })),
    ]);
    await processGlobalOperation("asia", unblockOperationId, runtime);
    const [inactive, completed] = await Promise.all([
      destinationRef.get(),
      unblockOperationRef.get(),
    ]);
    const completedAt = completed.get("completedAt") as Timestamp;
    const expireAt = inactive.get("expireAt") as Timestamp;
    assert.equal(inactive.get("isBlocked"), false);
    assert.equal(inactive.get("revision"), 2);
    assert.equal(
      expireAt.toMillis(),
      completedAt.toMillis() + BLOCK_TOMBSTONE_RETENTION_MILLIS,
    );
  },
);

firestoreContractTest(
  "updates local profile snapshots and rejects an older replay",
  async () => {
    const {runId, europe} = requireContext();
    const uid = `snapshot-${runId}`;
    const placeRef = europe.collection("places").doc(`place-${runId}`);
    const memberRef = placeRef.collection("members").doc(uid);
    trackForCleanup(placeRef, memberRef);
    const now = Timestamp.now();
    await Promise.all([
      placeRef.set({
        createdByUserId: uid,
        isArchived: false,
        creatorName: "Old",
        creatorPhotoUrl: null,
        creatorPhotoVersion: 1,
        creatorProfileRevision: 1,
      }),
      memberRef.set({
        userId: uid,
        displayName: "Old",
        profileRevision: 1,
      }),
    ]);
    const currentProfile = {
      displayName: "Current",
      photoUrl: "https://example.com/current.png",
      photoVersion: 2,
      revision: 2,
      followerCount: 0,
      followingCount: 0,
      createdAt: now,
      updatedAt: now,
    };
    await syncProfileSnapshots(europe, uid, currentProfile);
    await syncProfileSnapshots(europe, uid, {
      ...currentProfile,
      displayName: "Stale",
      revision: 1,
    });
    const [place, member] = await Promise.all([
      placeRef.get(),
      memberRef.get(),
    ]);

    assert.equal(place.get("creatorName"), "Current");
    assert.equal(place.get("creatorProfileRevision"), 2);
    assert.equal(member.get("displayName"), "Current");
    assert.equal(member.get("profileRevision"), 2);
  },
);

firestoreContractTest(
  "leases, checkpoints, and completes one cleanup job",
  async () => {
    const {runId, asia, provider} = requireContext();
    const input = {
      sourceOperationId: `contract-${runId}`,
      entityType: "profile",
      entityId: runId,
      revision: 1,
      world: "asia",
      queue: "firestore" as const,
      jobType: "cleanupContractEntity",
    };
    const jobId = cleanupJobId(input);
    const jobRef = asia.doc(`cleanupQueues/firestore/jobs/${jobId}`);
    trackForCleanup(jobRef);
    await jobRef.create(newCleanupJobData(input, Timestamp.now()));

    const observedCursors: Array<string | null> = [];
    const handler: CleanupJobHandler = {
      queue: "firestore",
      jobType: "cleanupContractEntity",
      processBatch: async ({job}) => {
        observedCursors.push(job.cursor);
        return job.cursor === null ?
          {complete: false, cursor: "page-1"} :
          {complete: true};
      },
    };
    const runtime = {
      catalog: WORLD_CATALOG,
      firestore: provider,
      handlers: new CleanupJobHandlerRegistry([handler]),
    };

    const first = await processCleanupJob(
      "asia",
      "firestore",
      jobId,
      runtime,
    );
    const replay = await processCleanupJob(
      "asia",
      "firestore",
      jobId,
      runtime,
    );
    const completed = await jobRef.get();

    assert.deepEqual(observedCursors, [null, "page-1"]);
    assert.equal(first.status, "complete");
    assert.equal(first.processed, true);
    assert.equal(replay.status, "complete");
    assert.equal(replay.processed, false);
    assert.equal(completed.get("attemptCount"), 1);
    assert.equal(completed.get("status"), "complete");
    assert.notEqual(completed.get("completedAt"), null);
    assert.notEqual(completed.get("expireAt"), null);
  },
);

firestoreContractTest(
  "account deletion removes an administrator-managed owned note",
  async () => {
    const {runId, asia} = requireContext();
    const ownerUid = `owner-${runId}`;
    const administratorUid = `administrator-${runId}`;
    const deletionId = accountDeletionId(ownerUid);
    const requestedAt = Timestamp.now();
    const placeRef = asia.collection("places").doc(`owned-${runId}`);
    const administratorRef = placeRef.collection("administrators")
      .doc(administratorUid);
    const participantMessageRef = placeRef.collection("messages")
      .doc("participant-message");
    const administratorAccountRef = asia.collection("users")
      .doc(administratorUid);
    const targetRef = asia.collection("accountDeletionFirestoreTargets")
      .doc(deletionId);
    const input = {
      sourceOperationId: deletionId,
      entityType: "accountDeletion",
      entityId: deletionId,
      revision: 1,
      world: "asia",
      queue: "firestore" as const,
      jobType: DELETE_ACCOUNT_DATA_JOB,
    };
    const jobId = cleanupJobId(input);
    trackForCleanup(
      administratorRef,
      participantMessageRef,
      placeRef,
      administratorAccountRef,
      targetRef,
    );
    await Promise.all([
      placeRef.set({
        createdByUserId: ownerUid,
        administratorCount: 1,
      }),
      administratorRef.set({
        userId: administratorUid,
        invitedByUid: ownerUid,
      }),
      participantMessageRef.set({
        userId: `participant-${runId}`,
        content: "participant content",
      }),
      administratorAccountRef.set({displayName: "Administrator"}),
      targetRef.set({
        uid: ownerUid,
        ownedPlaceIds: [placeRef.id],
        requestedAt,
      }),
    ]);

    let job = newCleanupJobData(input, requestedAt);
    let completed = false;
    for (let batch = 0; batch < 32; batch += 1) {
      const result = await accountDeletionFirestoreHandler.processBatch({
        queue: "firestore",
        firestore: asia,
        jobId,
        job,
      });
      if (result.complete) {
        completed = true;
        break;
      }
      job = {...job, cursor: result.cursor};
    }

    const [place, administrator, message, administratorAccount, target] =
      await Promise.all([
        placeRef.get(),
        administratorRef.get(),
        participantMessageRef.get(),
        administratorAccountRef.get(),
        targetRef.get(),
      ]);
    assert.equal(completed, true);
    assert.equal(place.exists, false);
    assert.equal(administrator.exists, false);
    assert.equal(message.exists, false);
    assert.equal(administratorAccount.exists, true);
    assert.equal(target.exists, false);
  },
);

firestoreContractTest(
  "leases and completes one moderation job exactly once",
  async () => {
    const {runId, asia, provider} = requireContext();
    const input = {
      jobType: "evaluateContractMessage",
      targetPath: `places/test-${runId}/messages/test-message`,
      inputHash: "c".repeat(64),
      world: "asia",
    };
    const jobId = moderationJobId(input);
    const jobRef = asia.collection("moderationJobs").doc(jobId);
    trackForCleanup(jobRef);
    await jobRef.create(newModerationJobData(input, Timestamp.now()));

    let invocationCount = 0;
    const handler: ModerationJobHandler = {
      jobType: input.jobType,
      process: async () => {
        invocationCount += 1;
      },
    };
    const runtime = {
      catalog: WORLD_CATALOG,
      firestore: provider,
      handlers: new ModerationJobHandlerRegistry([handler]),
    };

    const first = await processModerationJob("asia", jobId, runtime);
    const replay = await processModerationJob("asia", jobId, runtime);
    const completed = await jobRef.get();

    assert.equal(invocationCount, 1);
    assert.equal(first.status, "complete");
    assert.equal(first.processed, true);
    assert.equal(replay.status, "complete");
    assert.equal(replay.processed, false);
    assert.equal(completed.get("attemptCount"), 1);
    assert.notEqual(completed.get("completedAt"), null);
    assert.notEqual(completed.get("expireAt"), null);
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
 * @param {string} marker Three hexadecimal fixture marker characters.
 * @return {string} Valid deterministic UUID v7 test fixture.
 */
function testOperationId(runId: string, marker = "00a"): string {
  const suffix = runId.replace(/-/g, "").slice(0, 12);
  return `00000000-0000-7${marker}-800b-${suffix}`;
}

interface PendingOperationInput {
  readonly operationId: string;
  readonly operationType: string;
  readonly entityId: string;
  readonly ownerUid: string;
  readonly revision: number;
  readonly acceptedAt: Timestamp;
}

/**
 * Creates one two-world pending operation fixture.
 *
 * @param {PendingOperationInput} input Stable operation fields.
 * @return {object} Persistable pending operation document.
 */
function pendingOperationData(input: PendingOperationInput) {
  return {
    operationId: input.operationId,
    operationType: input.operationType,
    entityId: input.entityId,
    revision: input.revision,
    authorityWorld: "asia",
    ownerUid: input.ownerUid,
    payloadHash: "b".repeat(64),
    status: "pending",
    acceptedAt: input.acceptedAt,
    worldCatalogVersion: 1,
    requiredWorlds: ["asia", "europe"],
    worldAcks: {
      asia: {
        revision: input.revision,
        acknowledgedAt: input.acceptedAt,
      },
    },
    createdAt: input.acceptedAt,
    updatedAt: input.acceptedAt,
  };
}
