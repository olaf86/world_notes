import assert from "node:assert/strict";
import test from "node:test";

import {App} from "firebase-admin/app";
import {Firestore} from "firebase-admin/firestore";
import {onDocumentCreated} from "firebase-functions/v2/firestore";

import {
  createAdminWorldFirestoreClient,
  DEFAULT_FIRESTORE_DATABASE_ID,
  WorldDatabaseConfig,
  WorldFirestoreDatabaseId,
  WorldFirestoreProvider,
} from "../src/platform/worldFirestoreProvider";

const worldDatabases = [
  {worldId: "asia", databaseId: DEFAULT_FIRESTORE_DATABASE_ID},
  {worldId: "northAmerica", databaseId: "north-america"},
  {worldId: "europe", databaseId: "europe"},
] as const satisfies readonly WorldDatabaseConfig[];

/**
 * Produces the minimum Firestore client shape used by the provider.
 *
 * @param {string} databaseId Database ID exposed by the fake client.
 * @return {Firestore} Fake Firestore client.
 */
function fakeFirestore(databaseId: string): Firestore {
  return {databaseId} as Firestore;
}

test("resolves allowlisted default and named databases", () => {
  const requestedDatabaseIds: string[] = [];
  const provider = new WorldFirestoreProvider(worldDatabases, {
    appProvider: () => ({} as App),
    clientFactory: (_app, databaseId) => {
      requestedDatabaseIds.push(databaseId);
      return fakeFirestore(databaseId);
    },
  });

  assert.equal(provider.forWorld("asia").databaseId, "(default)");
  assert.equal(provider.forWorld("europe").databaseId, "europe");
  assert.deepEqual(requestedDatabaseIds, ["(default)", "europe"]);
});

test("caches one client per allowlisted database", () => {
  let factoryCalls = 0;
  const provider = new WorldFirestoreProvider(worldDatabases, {
    appProvider: () => ({} as App),
    clientFactory: (_app, databaseId) => {
      factoryCalls += 1;
      return fakeFirestore(databaseId);
    },
  });

  const first = provider.forWorld("northAmerica");
  const second = provider.forWorld("northAmerica");

  assert.equal(first, second);
  assert.equal(factoryCalls, 1);
});

test("rejects unknown worlds before constructing a client", () => {
  let factoryCalls = 0;
  const provider = new WorldFirestoreProvider(worldDatabases, {
    appProvider: () => ({} as App),
    clientFactory: (_app, databaseId) => {
      factoryCalls += 1;
      return fakeFirestore(databaseId);
    },
  });

  assert.throws(
    () => provider.forWorld("unknown"),
    /Unknown or inactive world ID/,
  );
  assert.equal(factoryCalls, 0);
});

test("rejects a client whose resolved database does not match", () => {
  const provider = new WorldFirestoreProvider(worldDatabases, {
    appProvider: () => ({} as App),
    clientFactory: () => fakeFirestore("(default)"),
  });

  assert.throws(
    () => provider.forWorld("europe"),
    /Firestore database route mismatch/,
  );
});

test("rejects duplicate or unsupported catalog mappings", () => {
  assert.throws(
    () => new WorldFirestoreProvider([
      {worldId: "asia", databaseId: "(default)"},
      {worldId: "asia", databaseId: "europe"},
    ]),
    /Duplicate world ID/,
  );
  assert.throws(
    () => new WorldFirestoreProvider([
      {worldId: "asia", databaseId: "(default)"},
      {worldId: "alias", databaseId: "(default)"},
    ]),
    /Duplicate database ID/,
  );
  assert.throws(
    () => new WorldFirestoreProvider(
      [
        {worldId: "future", databaseId: "future-database"},
      ] as unknown as readonly WorldDatabaseConfig[],
    ),
    /Unsupported Firestore database ID/,
  );
});

test("the Admin client factory also rejects an unsupported database", () => {
  assert.throws(
    () => createAdminWorldFirestoreClient(
      {} as App,
      "future-database" as WorldFirestoreDatabaseId,
    ),
    /Unsupported Firestore database ID/,
  );
});

test("Functions v2 manifest binds a trigger to a named database", () => {
  const trigger = onDocumentCreated(
    {
      database: "europe",
      document: "__firestore_named_database_probe__/{documentId}",
    },
    () => undefined,
  );

  assert.equal(
    trigger.__endpoint.eventTrigger?.eventFilters.database,
    "europe",
  );
  assert.equal(
    trigger.__endpoint.eventTrigger?.eventFilterPathPatterns?.document,
    "__firestore_named_database_probe__/{documentId}",
  );
});
