import assert from "node:assert/strict";
import test from "node:test";

import {App} from "firebase-admin/app";
import {Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {syncCreatorPhotoSnapshot} from
  "../src/creatorProfileSnapshots";
import {CallableRouteValidator} from
  "../src/platform/callableRouteValidator";
import {
  WorldBucket,
  WorldBucketProvider,
} from "../src/platform/worldBucketProvider";
import {WORLD_CATALOG} from "../src/platform/worldCatalog";
import {WorldContextProvider} from "../src/platform/worldContext";
import {
  WorldDatabaseConfig,
  WorldFirestoreDatabaseId,
  WorldFirestoreProvider,
} from "../src/platform/worldFirestoreProvider";
import {
  ASIA_WORLD_ID,
  WorldRegistry,
} from "../src/platform/worldRegistry";

const registry = new WorldRegistry(WORLD_CATALOG);
const worldDatabases = WORLD_CATALOG.worlds.map((world) => ({
  worldId: world.worldId,
  databaseId: world.databaseId as WorldFirestoreDatabaseId,
})) satisfies readonly WorldDatabaseConfig[];

/**
 * Produces the minimum Firestore shape used by the context provider.
 *
 * @param {string} databaseId Fake database ID.
 * @return {Firestore} Fake client.
 */
function fakeFirestore(databaseId: string): Firestore {
  return {databaseId} as Firestore;
}

/**
 * Produces the minimum Storage bucket shape used by the context provider.
 *
 * @param {string} name Fake bucket name.
 * @return {WorldBucket} Fake bucket client.
 */
function fakeBucket(name: string): WorldBucket {
  return {name} as unknown as WorldBucket;
}

test("resolves one aligned Asia context and caches it", () => {
  let firestoreFactoryCalls = 0;
  let bucketFactoryCalls = 0;
  const firestoreProvider = new WorldFirestoreProvider(worldDatabases, {
    appProvider: () => ({} as App),
    clientFactory: (_app, databaseId) => {
      firestoreFactoryCalls += 1;
      return fakeFirestore(databaseId);
    },
  });
  const bucketProvider = new WorldBucketProvider(registry, {
    appProvider: () => ({} as App),
    bucketFactory: (_app, bucketName) => {
      bucketFactoryCalls += 1;
      return fakeBucket(bucketName);
    },
  });
  const provider = new WorldContextProvider(registry, {
    firestoreProvider,
    bucketProvider,
  });

  const first = provider.forContentWorld(ASIA_WORLD_ID);
  const second = provider.forContentWorld(ASIA_WORLD_ID);

  assert.equal(first, second);
  assert.equal(first.worldId, "asia");
  assert.equal(first.firestore.databaseId, "(default)");
  assert.equal(
    first.bucket.name,
    "world-notes-prod.firebasestorage.app",
  );
  assert.equal(first.descriptor.functionsRegion, "asia-northeast1");
  assert.equal(firestoreFactoryCalls, 1);
  assert.equal(bucketFactoryCalls, 1);
});

test("rejects a provisioning world before creating regional clients", () => {
  let firestoreFactoryCalls = 0;
  let bucketFactoryCalls = 0;
  const provider = new WorldContextProvider(registry, {
    firestoreProvider: new WorldFirestoreProvider(worldDatabases, {
      appProvider: () => ({} as App),
      clientFactory: (_app, databaseId) => {
        firestoreFactoryCalls += 1;
        return fakeFirestore(databaseId);
      },
    }),
    bucketProvider: new WorldBucketProvider(registry, {
      appProvider: () => ({} as App),
      bucketFactory: (_app, bucketName) => {
        bucketFactoryCalls += 1;
        return fakeBucket(bucketName);
      },
    }),
  });

  assert.throws(
    () => provider.forContentWorld("europe"),
    /not enabled for content access/,
  );
  assert.equal(firestoreFactoryCalls, 0);
  assert.equal(bucketFactoryCalls, 0);
});

test("rejects a bucket returned for the wrong world", () => {
  const provider = new WorldBucketProvider(registry, {
    appProvider: () => ({} as App),
    bucketFactory: () => fakeBucket("wrong-bucket"),
  });

  assert.throws(
    () => provider.forWorld(ASIA_WORLD_ID),
    /Storage bucket route mismatch/,
  );
});

test("rejects dependencies routed by a different world mapping", () => {
  const mismatchedFirestoreProvider = new WorldFirestoreProvider(
    [{worldId: ASIA_WORLD_ID, databaseId: "europe"}],
    {
      appProvider: () => ({} as App),
      clientFactory: (_app, databaseId) => fakeFirestore(databaseId),
    },
  );
  const bucketProvider = new WorldBucketProvider(registry, {
    appProvider: () => ({} as App),
    bucketFactory: (_app, bucketName) => fakeBucket(bucketName),
  });
  const provider = new WorldContextProvider(registry, {
    firestoreProvider: mismatchedFirestoreProvider,
    bucketProvider,
  });

  assert.throws(
    () => provider.forContentWorld(ASIA_WORLD_ID),
    /World dependency route mismatch/,
  );
});

test("validates an explicit callable route against its deployment", () => {
  const validator = new CallableRouteValidator(registry);

  assert.equal(
    validator.requireContentRoute("asia", ASIA_WORLD_ID).databaseId,
    "(default)",
  );
  assert.throws(
    () => validator.requireContentRoute(undefined, ASIA_WORLD_ID),
    (error: unknown) =>
      error instanceof HttpsError && error.code === "invalid-argument",
  );
  assert.throws(
    () => validator.requireContentRoute("europe", ASIA_WORLD_ID),
    (error: unknown) =>
      error instanceof HttpsError && error.code === "failed-precondition",
  );
});

test("binds the Asia Firestore trigger to the default database", () => {
  assert.equal(
    syncCreatorPhotoSnapshot.__endpoint.eventTrigger?.eventFilters.database,
    "(default)",
  );
});
