import assert from "node:assert/strict";
import test from "node:test";

import {Timestamp} from "firebase-admin/firestore";

import {
  canonicalPayloadHash,
  derivedGlobalOperationId,
  GLOBAL_COMMAND_SCOPE,
  GlobalOperationValidationError,
  newGlobalOperationId,
  parseGlobalOperation,
  requireOperationId,
  revisionedTombstone,
  snapshotRequiredWorlds,
} from "../src/globalOperations";
import {WorldCatalog} from "../src/platform/worldCatalog";

const TEST_OPERATION_ID = "00000000-0000-700a-800b-000000000001";
const OTHER_TEST_OPERATION_ID = "00000000-0000-700a-800b-000000000002";

test("canonical payload hashes ignore object key order", () => {
  const first = canonicalPayloadHash({
    languagePreference: "ja",
    nested: {enabled: true, count: 2},
  });
  const second = canonicalPayloadHash({
    nested: {count: 2, enabled: true},
    languagePreference: "ja",
  });

  assert.equal(first, second);
  assert.match(first, /^[0-9a-f]{64}$/);
  assert.notEqual(
    first,
    canonicalPayloadHash({languagePreference: "en"}),
  );
});

test("rejects unsupported or unbounded canonical payload values", () => {
  assert.throws(
    () => canonicalPayloadHash({value: Number.NaN}),
    GlobalOperationValidationError,
  );
  assert.throws(
    () => canonicalPayloadHash({value: undefined}),
    GlobalOperationValidationError,
  );
  assert.throws(
    () => canonicalPayloadHash({value: "x".repeat(16_385)}),
    GlobalOperationValidationError,
  );
});

test("operation IDs are lowercase UUID v7 values", () => {
  assert.equal(requireOperationId(TEST_OPERATION_ID), TEST_OPERATION_ID);
  assert.throws(
    () => requireOperationId("9c981950-3f3b-4db0-8505-3c5b7789ac83"),
    GlobalOperationValidationError,
  );
  assert.throws(
    () => requireOperationId(TEST_OPERATION_ID.toUpperCase()),
    GlobalOperationValidationError,
  );
});

test("server-originated operation IDs retain their UUID v7 timestamp", () => {
  const timestamp = 1_750_000_000_123;
  const operationId = newGlobalOperationId(timestamp);
  const encodedTimestamp = Number.parseInt(
    operationId.replace(/-/g, "").slice(0, 12),
    16,
  );

  assert.equal(requireOperationId(operationId), operationId);
  assert.equal(encodedTimestamp, timestamp);
});

test("derived operation IDs are stable, distinct UUID v7 values", () => {
  const first = derivedGlobalOperationId(
    TEST_OPERATION_ID,
    "follow:alice:bob",
  );
  const retry = derivedGlobalOperationId(
    TEST_OPERATION_ID,
    "follow:alice:bob",
  );
  const reverse = derivedGlobalOperationId(
    TEST_OPERATION_ID,
    "follow:bob:alice",
  );

  assert.equal(first, retry);
  assert.notEqual(first, reverse);
  assert.equal(requireOperationId(first), first);
  assert.equal(
    first.replace(/-/g, "").slice(0, 12),
    TEST_OPERATION_ID.replace(/-/g, "").slice(0, 12),
  );
});

test("required worlds snapshot only active catalog membership", () => {
  const catalog = testCatalog();

  assert.deepEqual(
    snapshotRequiredWorlds(
      catalog,
      "asia",
      GLOBAL_COMMAND_SCOPE.authorityOnly,
    ),
    ["asia"],
  );
  assert.deepEqual(
    snapshotRequiredWorlds(
      catalog,
      "asia",
      GLOBAL_COMMAND_SCOPE.allActiveWorlds,
    ),
    ["asia", "europe"],
  );
  assert.throws(
    () => snapshotRequiredWorlds(
      catalog,
      "northAmerica",
      GLOBAL_COMMAND_SCOPE.allActiveWorlds,
    ),
    GlobalOperationValidationError,
  );
});

test("revisioned tombstones require a positive safe revision", () => {
  const deletedAt = Timestamp.fromMillis(1_000);

  assert.deepEqual(revisionedTombstone(3, deletedAt), {
    revision: 3,
    isDeleted: true,
    deletedAt,
  });
  assert.throws(
    () => revisionedTombstone(0, deletedAt),
    GlobalOperationValidationError,
  );
});

test("operation parser enforces schema and terminal invariants", () => {
  const completedAt = Timestamp.fromMillis(1_000);
  const valid = {
    operationId: TEST_OPERATION_ID,
    operationType: "setLanguagePreference",
    entityId: "alice",
    revision: 1,
    authorityWorld: "asia",
    ownerUid: "alice",
    payloadHash: "a".repeat(64),
    status: "complete",
    acceptedAt: completedAt,
    worldCatalogVersion: 1,
    requiredWorlds: ["asia"],
    worldAcks: {
      asia: {revision: 1, acknowledgedAt: completedAt},
    },
    createdAt: completedAt,
    updatedAt: completedAt,
    completedAt,
    expireAt: Timestamp.fromMillis(2_000),
  };

  assert.equal(parseGlobalOperation(valid, TEST_OPERATION_ID).revision, 1);
  assert.throws(
    () => parseGlobalOperation(
      {...valid, extraData: true},
      TEST_OPERATION_ID,
    ),
    /fields are invalid/,
  );
  assert.throws(
    () => parseGlobalOperation(
      {...valid, worldAcks: {}},
      TEST_OPERATION_ID,
    ),
    /authority acknowledgement/,
  );
  assert.throws(
    () => parseGlobalOperation(
      {...valid, status: "pending"},
      TEST_OPERATION_ID,
    ),
    /Pending global operation/,
  );
  assert.throws(
    () => parseGlobalOperation(valid, OTHER_TEST_OPERATION_ID),
    /does not match its document path/,
  );
});

/**
 * Returns a catalog containing active, mirror-only and provisioning worlds.
 *
 * @return {WorldCatalog} Test catalog.
 */
function testCatalog(): WorldCatalog {
  return {
    schemaVersion: 1,
    catalogVersion: 7,
    worlds: [
      {
        worldId: "asia",
        databaseId: "(default)",
        firestoreLocation: "asia-northeast1",
        functionsRegion: "asia-northeast1",
        bucketName: "example.firebasestorage.app",
        displayNameKey: "world.asia",
        catalogState: "homeEnabled",
        homeAssignmentEnabled: true,
        contentAccessEnabled: true,
      },
      {
        worldId: "northAmerica",
        databaseId: "north-america",
        firestoreLocation: "us-central1",
        functionsRegion: "us-central1",
        bucketName: "north-america.example.firebasestorage.app",
        displayNameKey: "world.northAmerica",
        catalogState: "provisioning",
        homeAssignmentEnabled: false,
        contentAccessEnabled: false,
      },
      {
        worldId: "europe",
        databaseId: "europe",
        firestoreLocation: "europe-west1",
        functionsRegion: "europe-west1",
        bucketName: "europe.example.firebasestorage.app",
        displayNameKey: "world.europe",
        catalogState: "mirrorOnly",
        homeAssignmentEnabled: false,
        contentAccessEnabled: false,
      },
    ],
  };
}
