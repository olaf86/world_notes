/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {Timestamp} from "firebase-admin/firestore";

import {
  cleanupJobId,
  cleanupRetryDelayMillis,
  CleanupJobData,
  CleanupJobHandler,
  CleanupJobHandlerRegistry,
  deriveCleanupJobAttention,
  newCleanupJobData,
  parseCleanupJob,
} from "../src/cleanupJobs";
import {
  processAsiaFirestoreCleanupJob,
  processAsiaStorageCleanupJob,
  processEuropeFirestoreCleanupJob,
  processEuropeStorageCleanupJob,
  processNorthAmericaFirestoreCleanupJob,
  processNorthAmericaStorageCleanupJob,
  reconcileAsiaFirestoreCleanupJobs,
  reconcileAsiaStorageCleanupJobs,
  reconcileEuropeFirestoreCleanupJobs,
  reconcileEuropeStorageCleanupJobs,
  reconcileNorthAmericaFirestoreCleanupJobs,
  reconcileNorthAmericaStorageCleanupJobs,
} from "../src/cleanupTriggers";

const TEST_SOURCE_OPERATION_ID = "test-source-operation";
const CREATED_AT = Timestamp.fromMillis(1_000);

test("cleanup IDs are deterministic and partition-sensitive", () => {
  const input = testInput();
  const first = cleanupJobId(input);

  assert.equal(cleanupJobId({...input}), first);
  assert.match(first, /^[0-9a-f]{64}$/);
  assert.notEqual(cleanupJobId({...input, partition: "second"}), first);
  assert.notEqual(cleanupJobId({...input, queue: "storage"}), first);
});

test("new cleanup data satisfies the pending job contract", () => {
  const data = newCleanupJobData(testInput(), CREATED_AT);
  const parsed = parseCleanupJob(data, "asia");

  assert.equal(parsed.status, "pending");
  assert.equal(parsed.attemptCount, 0);
  assert.equal(parsed.nextAttemptAt?.toMillis(), CREATED_AT.toMillis());
  assert.equal(parsed.leaseUntil, null);
  assert.equal(parsed.expireAt, null);
});

test("cleanup parser rejects route and lifecycle contradictions", () => {
  const pending = newCleanupJobData(testInput(), CREATED_AT);

  assert.throws(
    () => parseCleanupJob(pending, "europe"),
    /does not match its database route/,
  );
  assert.throws(
    () => parseCleanupJob({...pending, leaseUntil: CREATED_AT}, "asia"),
    /Pending cleanup job fields/,
  );
  assert.throws(
    () => parseCleanupJob({...pending, extra: true}, "asia"),
    /fields are invalid/,
  );
});

test("handler registry owns each queue and type explicitly", () => {
  const firestore = testHandler("firestore", "deleteSnapshots");
  const storage = testHandler("storage", "deleteObject");
  const registry = new CleanupJobHandlerRegistry([firestore, storage]);

  assert.equal(registry.require("firestore", "deleteSnapshots"), firestore);
  assert.equal(registry.require("storage", "deleteObject"), storage);
  assert.throws(
    () => registry.require("storage", "deleteSnapshots"),
    /No cleanup handler/,
  );
  assert.throws(
    () => new CleanupJobHandlerRegistry([firestore, firestore]),
    /Duplicate cleanup handler/,
  );
});

test("cleanup retry timing follows the approved schedule", () => {
  const neutralJitter = 0.5;

  assert.equal(cleanupRetryDelayMillis(1, neutralJitter), 10 * 60 * 1000);
  assert.equal(cleanupRetryDelayMillis(2, neutralJitter), 30 * 60 * 1000);
  assert.equal(cleanupRetryDelayMillis(3, neutralJitter), 2 * 60 * 60 * 1000);
  assert.equal(cleanupRetryDelayMillis(4, neutralJitter), 6 * 60 * 60 * 1000);
  assert.equal(cleanupRetryDelayMillis(5, neutralJitter), 24 * 60 * 60 * 1000);
  assert.equal(cleanupRetryDelayMillis(20, neutralJitter), 24 * 60 * 60 * 1000);
});

test("cleanup attention is derived from age and terminal state", () => {
  const pending = newCleanupJobData(testInput(), CREATED_AT);
  const warningAt = Timestamp.fromMillis(
    CREATED_AT.toMillis() + 60 * 60 * 1000,
  );
  const criticalAt = Timestamp.fromMillis(
    CREATED_AT.toMillis() + 24 * 60 * 60 * 1000,
  );
  const complete = completedJob(pending, warningAt);

  assert.equal(deriveCleanupJobAttention(pending, warningAt), "warning");
  assert.equal(deriveCleanupJobAttention(pending, criticalAt), "critical");
  assert.equal(deriveCleanupJobAttention(complete, criticalAt), "none");
});

test("cleanup triggers use each queue path and regional database", () => {
  const cases = [
    [
      processAsiaFirestoreCleanupJob,
      "(default)",
      "asia-northeast1",
      "firestore",
    ],
    [
      processNorthAmericaFirestoreCleanupJob,
      "north-america",
      "us-central1",
      "firestore",
    ],
    [processEuropeFirestoreCleanupJob, "europe", "europe-west1", "firestore"],
    [processAsiaStorageCleanupJob, "(default)", "asia-northeast1", "storage"],
    [
      processNorthAmericaStorageCleanupJob,
      "north-america",
      "us-central1",
      "storage",
    ],
    [processEuropeStorageCleanupJob, "europe", "europe-west1", "storage"],
  ] as const;

  for (const [trigger, database, region, queue] of cases) {
    assert.equal(triggerDatabase(trigger), database);
    assert.equal(triggerRegion(trigger), region);
    assert.equal(
      triggerDocument(trigger),
      `cleanupQueues/${queue}/jobs/{jobId}`,
    );
  }
});

test("cleanup reconcilers are deployed with their regional workers", () => {
  const cases = [
    [reconcileAsiaFirestoreCleanupJobs, "asia-northeast1"],
    [reconcileNorthAmericaFirestoreCleanupJobs, "us-central1"],
    [reconcileEuropeFirestoreCleanupJobs, "europe-west1"],
    [reconcileAsiaStorageCleanupJobs, "asia-northeast1"],
    [reconcileNorthAmericaStorageCleanupJobs, "us-central1"],
    [reconcileEuropeStorageCleanupJobs, "europe-west1"],
  ] as const;

  for (const [schedule, region] of cases) {
    assert.equal(scheduleRegion(schedule), region);
  }
});

function testInput() {
  return {
    sourceOperationId: TEST_SOURCE_OPERATION_ID,
    entityType: "profile",
    entityId: "test-user",
    revision: 3,
    world: "asia",
    queue: "firestore" as const,
    jobType: "deleteSnapshots",
  };
}

function testHandler(
  queue: CleanupJobHandler["queue"],
  jobType: string,
): CleanupJobHandler {
  return {
    queue,
    jobType,
    processBatch: async () => ({complete: true}),
  };
}

function completedJob(
  pending: CleanupJobData,
  completedAt: Timestamp,
): CleanupJobData {
  return parseCleanupJob({
    ...pending,
    status: "complete",
    nextAttemptAt: null,
    completedAt,
    updatedAt: completedAt,
    expireAt: Timestamp.fromMillis(
      completedAt.toMillis() + 30 * 24 * 60 * 60 * 1000,
    ),
  }, pending.world);
}

interface EventFunctionShape {
  readonly __endpoint: {
    readonly region?: readonly string[];
    readonly eventTrigger?: {
      readonly eventFilters?: Record<string, string>;
      readonly eventFilterPathPatterns?: Record<string, string>;
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

function triggerDocument(value: unknown): string | undefined {
  return (value as EventFunctionShape).__endpoint.eventTrigger
    ?.eventFilterPathPatterns?.document;
}

function triggerRegion(value: unknown): string | undefined {
  return (value as EventFunctionShape).__endpoint.region?.[0];
}

function scheduleRegion(value: unknown): string | undefined {
  return (value as ScheduleFunctionShape).__endpoint.region?.[0];
}
