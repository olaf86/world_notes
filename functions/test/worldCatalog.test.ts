import assert from "node:assert/strict";
import test from "node:test";

import {
  parseWorldCatalog,
  WORLD_CATALOG,
} from "../src/platform/worldCatalog";
import {
  WORLD_FIRESTORE_DATABASE_IDS,
} from "../src/platform/worldFirestoreProvider";

test("loads the current versioned world catalog", () => {
  assert.equal(WORLD_CATALOG.schemaVersion, 1);
  assert.equal(WORLD_CATALOG.catalogVersion, 5);
  assert.deepEqual(
    WORLD_CATALOG.worlds.map((world) => ({
      worldId: world.worldId,
      databaseId: world.databaseId,
      state: world.catalogState,
    })),
    [
      {
        worldId: "asia",
        databaseId: "(default)",
        state: "homeEnabled",
      },
      {
        worldId: "northAmerica",
        databaseId: "north-america",
        state: "homeEnabled",
      },
      {
        worldId: "europe",
        databaseId: "europe",
        state: "homeEnabled",
      },
    ],
  );
});

test("keeps the Firestore adapter allowlist aligned with the catalog", () => {
  assert.deepEqual(
    [...WORLD_FIRESTORE_DATABASE_IDS].sort(),
    WORLD_CATALOG.worlds
      .map((world) => world.databaseId)
      .sort(),
  );
});

test("rejects unknown and missing fields", () => {
  const catalog = mutableCatalog();
  catalog.unexpected = true;
  assert.throws(
    () => parseWorldCatalog(catalog),
    /catalog fields are invalid/,
  );

  const world = mutableCatalog();
  delete world.worlds[0].functionsRegion;
  assert.throws(
    () => parseWorldCatalog(world),
    /catalog\.worlds\[0\] fields are invalid/,
  );
});

test("rejects duplicate routing resources", () => {
  const duplicateWorld = mutableCatalog();
  duplicateWorld.worlds[1].worldId = "asia";
  assert.throws(
    () => parseWorldCatalog(duplicateWorld),
    /Duplicate worldId/,
  );

  const duplicateDatabase = mutableCatalog();
  duplicateDatabase.worlds[1].databaseId = "(default)";
  assert.throws(
    () => parseWorldCatalog(duplicateDatabase),
    /Duplicate databaseId/,
  );
});

test("rejects missing buckets and premature lifecycle flags", () => {
  const missingBucket = mutableCatalog();
  missingBucket.worlds[1].bucketName = null;
  assert.throws(
    () => parseWorldCatalog(missingBucket),
    /bucketName has an invalid format/,
  );

  const earlyContent = mutableCatalog();
  earlyContent.worlds[2].catalogState = "mirrorOnly";
  earlyContent.worlds[2].contentAccessEnabled = true;
  assert.throws(
    () => parseWorldCatalog(earlyContent),
    /contentAccessEnabled requires an enabled state/,
  );

  const earlyHome = mutableCatalog();
  earlyHome.worlds[0].catalogState = "contentEnabled";
  assert.throws(
    () => parseWorldCatalog(earlyHome),
    /homeAssignmentEnabled requires homeEnabled state/,
  );
});

test("exposes only explicitly home-enabled worlds for assignment", () => {
  const asia = WORLD_CATALOG.worlds[0];
  const northAmerica = WORLD_CATALOG.worlds[1];
  const europe = WORLD_CATALOG.worlds[2];

  assert.equal(asia.homeAssignmentEnabled, true);
  assert.equal(northAmerica.homeAssignmentEnabled, true);
  assert.equal(northAmerica.contentAccessEnabled, true);
  assert.equal(europe.homeAssignmentEnabled, true);
  assert.equal(europe.contentAccessEnabled, true);
});

test("rejects unsupported schema versions", () => {
  const catalog = mutableCatalog();
  catalog.schemaVersion = 2;

  assert.throws(
    () => parseWorldCatalog(catalog),
    /schemaVersion must be 1/,
  );
});

interface MutableWorld {
  worldId: string;
  databaseId: string;
  firestoreLocation: string;
  functionsRegion?: string;
  bucketName: string | null;
  displayNameKey: string;
  catalogState: string;
  homeAssignmentEnabled: boolean;
  contentAccessEnabled: boolean;
}

interface MutableCatalog {
  schemaVersion: number;
  catalogVersion: number;
  worlds: MutableWorld[];
  unexpected?: boolean;
}

/**
 * Produces a mutable JSON clone for invalid contract cases.
 *
 * @return {MutableCatalog} Mutable catalog clone.
 */
function mutableCatalog(): MutableCatalog {
  return JSON.parse(JSON.stringify(WORLD_CATALOG)) as MutableCatalog;
}
