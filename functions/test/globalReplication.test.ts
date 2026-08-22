/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {Timestamp} from "firebase-admin/firestore";

import {
  deriveGlobalOperationAttention,
  GlobalReplicationHandler,
  GlobalReplicationHandlerRegistry,
  missingDestinationWorlds,
} from "../src/globalReplication";
import {GlobalOperationData} from "../src/globalOperations";
import {
  reconcileAsiaGlobalOperations,
  reconcileEuropeGlobalOperations,
  reconcileNorthAmericaGlobalOperations,
  replicateAsiaGlobalOperation,
  replicateEuropeGlobalOperation,
  replicateNorthAmericaGlobalOperation,
} from "../src/globalReplicationTriggers";

const TEST_OPERATION_ID = "00000000-0000-700a-800b-000000000001";

test("handler registry requires one explicit owner per operation type", () => {
  const handler = testHandler("replicateTestEntity");
  const registry = new GlobalReplicationHandlerRegistry([handler]);

  assert.equal(registry.require("replicateTestEntity"), handler);
  assert.equal(registry.find("replicateTestEntity"), handler);
  assert.equal(registry.find("authorityOnlyOperation"), undefined);
  assert.throws(
    () => registry.require("unknownOperation"),
    /No global replication handler/,
  );
  assert.throws(
    () => new GlobalReplicationHandlerRegistry([handler, handler]),
    /Duplicate global replication handler/,
  );
});

test("missing destinations come only from the operation snapshot", () => {
  const operation = testOperation();

  assert.deepEqual(missingDestinationWorlds(operation), [
    "northAmerica",
    "europe",
  ]);
});

test("attention thresholds distinguish safety and ordinary operations", () => {
  const acceptedAt = Timestamp.fromMillis(1_000);
  const ordinary = testOperation({acceptedAt});
  const safety = testOperation({
    acceptedAt,
    operationType: "setUserBlock",
  });

  assert.equal(
    deriveGlobalOperationAttention(
      ordinary,
      Timestamp.fromMillis(acceptedAt.toMillis() + 59 * 60 * 1000),
    ),
    "none",
  );
  assert.equal(
    deriveGlobalOperationAttention(
      ordinary,
      Timestamp.fromMillis(acceptedAt.toMillis() + 60 * 60 * 1000),
    ),
    "warning",
  );
  assert.equal(
    deriveGlobalOperationAttention(
      safety,
      Timestamp.fromMillis(acceptedAt.toMillis() + 15 * 60 * 1000),
    ),
    "warning",
  );
  assert.equal(
    deriveGlobalOperationAttention(
      ordinary,
      Timestamp.fromMillis(acceptedAt.toMillis() + 24 * 60 * 60 * 1000),
    ),
    "critical",
  );
  assert.equal(
    deriveGlobalOperationAttention(
      testOperation({status: "complete"}),
      Timestamp.fromMillis(acceptedAt.toMillis() + 48 * 60 * 60 * 1000),
    ),
    "none",
  );
});

test("exports one trigger and reconciler per database route", () => {
  assert.equal(triggerDatabase(replicateAsiaGlobalOperation), "(default)");
  assert.equal(
    triggerDatabase(replicateNorthAmericaGlobalOperation),
    "north-america",
  );
  assert.equal(triggerDatabase(replicateEuropeGlobalOperation), "europe");
  assert.equal(
    triggerRegion(replicateAsiaGlobalOperation),
    "asia-northeast1",
  );
  assert.equal(
    triggerRegion(replicateNorthAmericaGlobalOperation),
    "us-central1",
  );
  assert.equal(triggerRegion(replicateEuropeGlobalOperation), "europe-west1");

  assert.equal(
    scheduleRegion(reconcileAsiaGlobalOperations),
    "asia-northeast1",
  );
  assert.equal(
    scheduleRegion(reconcileNorthAmericaGlobalOperations),
    "us-central1",
  );
  assert.equal(scheduleRegion(reconcileEuropeGlobalOperations), "europe-west1");
});

function testHandler(operationType: string): GlobalReplicationHandler {
  return {
    operationType,
    apply: async ({operation}) => operation.revision,
  };
}

function testOperation(
  overrides: Partial<GlobalOperationData> = {},
): GlobalOperationData {
  const acceptedAt = overrides.acceptedAt ?? Timestamp.fromMillis(1_000);
  const status = overrides.status ?? "pending";
  return {
    operationId: TEST_OPERATION_ID,
    operationType: "replicateTestEntity",
    entityId: "test-entity",
    revision: 1,
    authorityWorld: "asia",
    ownerUid: "test-owner",
    payloadHash: "a".repeat(64),
    status,
    acceptedAt,
    worldCatalogVersion: 1,
    requiredWorlds: ["asia", "northAmerica", "europe"],
    worldAcks: {
      asia: {revision: 1, acknowledgedAt: acceptedAt},
    },
    createdAt: acceptedAt,
    updatedAt: acceptedAt,
    ...overrides,
  };
}

interface EventFunctionShape {
  readonly __endpoint: {
    readonly region?: readonly string[];
    readonly eventTrigger?: {
      readonly eventFilters?: Record<string, string>;
    };
  };
}

interface ScheduleFunctionShape {
  readonly __endpoint: {readonly region?: readonly string[]};
}

function triggerDatabase(value: unknown): string | undefined {
  return (value as EventFunctionShape).__endpoint.eventTrigger
    ?.eventFilters?.database;
}

function triggerRegion(value: unknown): string | undefined {
  return (value as EventFunctionShape).__endpoint.region?.[0];
}

function scheduleRegion(value: unknown): string | undefined {
  return (value as ScheduleFunctionShape).__endpoint.region?.[0];
}
