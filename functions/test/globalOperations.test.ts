import assert from "node:assert/strict";
import test from "node:test";

import {Timestamp} from "firebase-admin/firestore";

import {
  canonicalPayloadHash,
  GlobalOperationValidationError,
  parseGlobalOperation,
  requireOperationId,
  revisionedTombstone,
  snapshotRequiredWorlds,
} from "../src/globalOperations";
import {WorldCatalog} from "../src/platform/worldCatalog";

const OPERATION_ID = "9c981950-3f3b-4db0-8505-3c5b7789ac83";

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

test("operation IDs are lowercase UUID v4 values", () => {
  assert.equal(requireOperationId(OPERATION_ID), OPERATION_ID);
  assert.throws(
    () => requireOperationId("01941f58-7c76-7a0b-9b6e-6f7798c18f22"),
    GlobalOperationValidationError,
  );
  assert.throws(
    () => requireOperationId(OPERATION_ID.toUpperCase()),
    GlobalOperationValidationError,
  );
});

test("required worlds snapshot only active catalog membership", () => {
  const catalog = testCatalog();

  assert.deepEqual(
    snapshotRequiredWorlds(catalog, "asia", "authorityOnly"),
    ["asia"],
  );
  assert.deepEqual(
    snapshotRequiredWorlds(catalog, "asia", "allActiveWorlds"),
    ["asia", "europe"],
  );
  assert.throws(
    () => snapshotRequiredWorlds(
      catalog,
      "northAmerica",
      "allActiveWorlds",
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
    operationId: OPERATION_ID,
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

  assert.equal(parseGlobalOperation(valid, OPERATION_ID).revision, 1);
  assert.throws(
    () => parseGlobalOperation({...valid, extraData: true}, OPERATION_ID),
    /fields are invalid/,
  );
  assert.throws(
    () => parseGlobalOperation({...valid, worldAcks: {}}, OPERATION_ID),
    /authority acknowledgement/,
  );
  assert.throws(
    () => parseGlobalOperation({...valid, status: "pending"}, OPERATION_ID),
    /Pending global operation/,
  );
  assert.throws(
    () => parseGlobalOperation(valid, "8b9c445e-c810-440f-bc22-b7559195891d"),
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
