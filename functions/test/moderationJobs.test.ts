/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {Timestamp} from "firebase-admin/firestore";

import {
  deriveModerationJobAttention,
  ModerationJobData,
  ModerationJobHandler,
  ModerationJobHandlerRegistry,
  moderationJobId,
  moderationRetryDelayMillis,
  newModerationJobData,
  parseModerationJob,
} from "../src/moderationJobs";
import {
  processAsiaModerationJob,
  processEuropeModerationJob,
  processNorthAmericaModerationJob,
  reconcileAsiaModerationJobs,
  reconcileEuropeModerationJobs,
  reconcileNorthAmericaModerationJobs,
} from "../src/moderationJobTriggers";
import {
  EVALUATE_MESSAGE_MODERATION_JOB,
  messageModerationInputHash,
  messageModerationJobHandler,
} from "../src/messageModeration";
import {
  EVALUATE_NOTE_MODERATION_JOB,
  noteModerationInputHash,
  noteModerationJobHandler,
} from "../src/noteModeration";

const CREATED_AT = Timestamp.fromMillis(1_000);
const TEST_INPUT_HASH = "a".repeat(64);

test("moderation job IDs bind the world, target, and immutable input", () => {
  const input = testInput();
  const jobId = moderationJobId(input);

  assert.equal(moderationJobId({...input}), jobId);
  assert.match(jobId, /^[0-9a-f]{64}$/);
  assert.notEqual(
    moderationJobId({...input, world: "europe"}),
    jobId,
  );
  assert.notEqual(
    moderationJobId({...input, inputHash: "b".repeat(64)}),
    jobId,
  );
});

test("new moderation data satisfies the pending job contract", () => {
  const input = testInput();
  const job = newModerationJobData(input, CREATED_AT);
  const parsed = parseModerationJob(job, job.jobId, "asia");

  assert.equal(parsed.jobType, "evaluateTestMessage");
  assert.equal(parsed.targetPath, "places/test-note/messages/test-message");
  assert.equal(parsed.status, "pending");
  assert.equal(parsed.attemptCount, 0);
  assert.equal(parsed.nextAttemptAt?.toMillis(), CREATED_AT.toMillis());
  assert.equal(parsed.leaseUntil, null);
  assert.equal(parsed.expireAt, null);
});

test("moderation parser rejects route and lifecycle contradictions", () => {
  const pending = newModerationJobData(testInput(), CREATED_AT);

  assert.throws(
    () => parseModerationJob(pending, "b".repeat(64), "asia"),
    /does not match its document path/,
  );
  assert.throws(
    () => parseModerationJob(pending, pending.jobId, "europe"),
    /does not match its database route/,
  );
  assert.throws(
    () => parseModerationJob({...pending, leaseUntil: CREATED_AT}),
    /Pending moderation job fields/,
  );
  assert.throws(
    () => parseModerationJob({...pending, extra: true}),
    /fields are invalid/,
  );
  assert.throws(
    () => newModerationJobData(
      {...testInput(), targetPath: "../users"},
      CREATED_AT,
    ),
    /targetPath/,
  );
});

test("handler registry requires one owner per moderation job type", () => {
  const handler = testHandler();
  const registry = new ModerationJobHandlerRegistry([handler]);

  assert.equal(registry.require("evaluateTestMessage"), handler);
  assert.throws(
    () => registry.require("unknownJob"),
    /No moderation handler/,
  );
  assert.throws(
    () => new ModerationJobHandlerRegistry([handler, handler]),
    /Duplicate moderation handler/,
  );
});

test(
  "message moderation binds the exact immutable content and image order",
  () => {
    const hash = messageModerationInputHash("hello", ["first", "second"]);

    assert.match(hash, /^[0-9a-f]{64}$/);
    assert.equal(
      messageModerationInputHash("hello", ["first", "second"]),
      hash,
    );
    assert.notEqual(
      messageModerationInputHash("hello", ["second", "first"]),
      hash,
    );
    assert.notEqual(
      messageModerationInputHash("hello!", ["first", "second"]),
      hash,
    );
  },
);

test("message moderation handler owns its explicit job type", () => {
  assert.equal(
    messageModerationJobHandler.jobType,
    EVALUATE_MESSAGE_MODERATION_JOB,
  );
});

test("note moderation binds the exact immutable title and subtitle", () => {
  const hash = noteModerationInputHash("Title", "Description");

  assert.match(hash, /^[0-9a-f]{64}$/);
  assert.equal(noteModerationInputHash("Title", "Description"), hash);
  assert.notEqual(noteModerationInputHash("Title!", "Description"), hash);
  assert.notEqual(noteModerationInputHash("Title", null), hash);
});

test("note moderation handler owns its explicit job type", () => {
  assert.equal(
    noteModerationJobHandler.jobType,
    EVALUATE_NOTE_MODERATION_JOB,
  );
});

test("moderation retry stays durable with an approved backoff", () => {
  const neutralJitter = 0.5;

  assert.equal(moderationRetryDelayMillis(1, neutralJitter), 60 * 1000);
  assert.equal(moderationRetryDelayMillis(2, neutralJitter), 5 * 60 * 1000);
  assert.equal(moderationRetryDelayMillis(3, neutralJitter), 15 * 60 * 1000);
  assert.equal(moderationRetryDelayMillis(4, neutralJitter), 60 * 60 * 1000);
  assert.equal(
    moderationRetryDelayMillis(5, neutralJitter),
    6 * 60 * 60 * 1000,
  );
  assert.equal(
    moderationRetryDelayMillis(20, neutralJitter),
    24 * 60 * 60 * 1000,
  );
});

test("moderation attention is derived from age and terminal state", () => {
  const pending = newModerationJobData(testInput(), CREATED_AT);
  const warningAt = Timestamp.fromMillis(
    CREATED_AT.toMillis() + 15 * 60 * 1000,
  );
  const criticalAt = Timestamp.fromMillis(
    CREATED_AT.toMillis() + 24 * 60 * 60 * 1000,
  );
  const complete = completedJob(pending, warningAt);

  assert.equal(deriveModerationJobAttention(pending, warningAt), "warning");
  assert.equal(deriveModerationJobAttention(pending, criticalAt), "critical");
  assert.equal(deriveModerationJobAttention(complete, criticalAt), "none");
});

test("moderation workers are routed to all three databases", () => {
  const triggers = [
    [processAsiaModerationJob, "(default)", "asia-northeast1"],
    [processNorthAmericaModerationJob, "north-america", "us-central1"],
    [processEuropeModerationJob, "europe", "europe-west1"],
  ] as const;
  for (const [trigger, database, region] of triggers) {
    assert.equal(triggerDatabase(trigger), database);
    assert.equal(triggerRegion(trigger), region);
    assert.equal(triggerDocument(trigger), "moderationJobs/{jobId}");
  }

  const schedules = [
    [reconcileAsiaModerationJobs, "asia-northeast1"],
    [reconcileNorthAmericaModerationJobs, "us-central1"],
    [reconcileEuropeModerationJobs, "europe-west1"],
  ] as const;
  for (const [schedule, region] of schedules) {
    assert.equal(scheduleRegion(schedule), region);
  }
});

function testInput() {
  return {
    jobType: "evaluateTestMessage",
    targetPath: "places/test-note/messages/test-message",
    inputHash: TEST_INPUT_HASH,
    world: "asia",
  };
}

function testHandler(): ModerationJobHandler {
  return {
    jobType: "evaluateTestMessage",
    process: async () => undefined,
  };
}

function completedJob(
  pending: ModerationJobData,
  completedAt: Timestamp,
): ModerationJobData {
  return parseModerationJob({
    ...pending,
    status: "complete",
    nextAttemptAt: null,
    completedAt,
    updatedAt: completedAt,
    expireAt: Timestamp.fromMillis(
      completedAt.toMillis() + 30 * 24 * 60 * 60 * 1000,
    ),
  }, pending.jobId, pending.world);
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
