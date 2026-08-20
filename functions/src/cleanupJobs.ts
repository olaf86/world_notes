/* eslint-disable valid-jsdoc */

import {createHash} from "node:crypto";

import {
  DocumentReference,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";

import {GLOBAL_OPERATION_TERMINAL_RETENTION_MILLIS} from "./globalOperations";
import {WorldFirestoreProvider} from "./platform/worldFirestoreProvider";
import {
  WorldBucket,
  WorldBucketProvider,
} from "./platform/worldBucketProvider";
import {WorldCatalog} from "./platform/worldCatalog";

export const CLEANUP_JOB_LEASE_MILLIS = 5 * 60 * 1000;
export const CLEANUP_JOB_WARNING_AFTER_MILLIS = 60 * 60 * 1000;
export const CLEANUP_JOB_CRITICAL_AFTER_MILLIS = 24 * 60 * 60 * 1000;
export const CLEANUP_JOB_RECONCILE_BATCH_SIZE = 50;
export const CLEANUP_JOB_MAX_BATCHES_PER_RUN = 10;

const JOB_TYPE_PATTERN = /^[a-z][A-Za-z0-9]{0,63}$/;
const VALUE_PATTERN = /^[^/\s]{1,256}$/;
const ERROR_CODE_PATTERN = /^[A-Za-z0-9_.:-]{1,128}$/;
const MAX_CURSOR_LENGTH = 4_096;
const JOB_FIELDS = new Set([
  "jobType",
  "sourceOperationId",
  "entityType",
  "entityId",
  "revision",
  "world",
  "status",
  "cursor",
  "attemptCount",
  "leaseUntil",
  "nextAttemptAt",
  "lastErrorCode",
  "createdAt",
  "updatedAt",
  "completedAt",
  "expireAt",
]);

export type CleanupJobQueue = "firestore" | "storage";
export type CleanupJobStatus = "pending" | "running" | "complete";
export type CleanupJobAttention = "none" | "warning" | "critical";

export interface CleanupJobData {
  readonly jobType: string;
  readonly sourceOperationId: string;
  readonly entityType: string;
  readonly entityId: string;
  readonly revision: number;
  readonly world: string;
  readonly status: CleanupJobStatus;
  readonly cursor: string | null;
  readonly attemptCount: number;
  readonly leaseUntil: Timestamp | null;
  readonly nextAttemptAt: Timestamp | null;
  readonly lastErrorCode: string | null;
  readonly createdAt: Timestamp;
  readonly updatedAt: Timestamp;
  readonly completedAt: Timestamp | null;
  readonly expireAt: Timestamp | null;
}

export interface NewCleanupJobInput {
  readonly sourceOperationId: string;
  readonly entityType: string;
  readonly entityId: string;
  readonly revision: number;
  readonly world: string;
  readonly queue: CleanupJobQueue;
  readonly jobType: string;
  readonly partition?: string;
}

export interface CleanupBatchContext {
  readonly queue: CleanupJobQueue;
  readonly firestore: Firestore;
  readonly jobId: string;
  readonly job: CleanupJobData;
  readonly bucket?: WorldBucket;
}

export type CleanupBatchResult =
  | {readonly complete: true}
  | {readonly complete: false; readonly cursor: string};

/** Owns one trusted cleanup job type in one queue. */
export interface CleanupJobHandler {
  readonly queue: CleanupJobQueue;
  readonly jobType: string;
  processBatch(context: CleanupBatchContext): Promise<CleanupBatchResult>;
}

/** Immutable queue-and-type allowlist for cleanup implementations. */
export class CleanupJobHandlerRegistry {
  private readonly handlers = new Map<string, CleanupJobHandler>();

  /** Creates a registry and rejects ambiguous handler ownership. */
  constructor(handlers: readonly CleanupJobHandler[]) {
    for (const handler of handlers) {
      requireQueue(handler.queue);
      requirePattern(handler.jobType, "jobType", JOB_TYPE_PATTERN);
      const key = handlerKey(handler.queue, handler.jobType);
      if (this.handlers.has(key)) {
        throw new Error(`Duplicate cleanup handler: ${key}.`);
      }
      this.handlers.set(key, handler);
    }
  }

  /** Returns the sole trusted handler for a queue and job type. */
  require(queue: CleanupJobQueue, jobType: string): CleanupJobHandler {
    const handler = this.handlers.get(handlerKey(queue, jobType));
    if (handler === undefined) {
      throw new Error(
        `No cleanup handler is registered for ${queue}:${jobType}.`,
      );
    }
    return handler;
  }
}

export interface CleanupRuntime {
  readonly catalog: WorldCatalog;
  readonly firestore: WorldFirestoreProvider;
  readonly handlers: CleanupJobHandlerRegistry;
  readonly buckets?: WorldBucketProvider;
  readonly now?: () => Timestamp;
  readonly random?: () => number;
}

export interface CleanupJobProcessResult {
  readonly jobId: string;
  readonly status: CleanupJobStatus | "missing";
  readonly processed: boolean;
}

interface ClaimedCleanupJob {
  readonly reference: DocumentReference;
  readonly job: CleanupJobData;
  readonly attempt: number;
}

/** Builds a deterministic document ID for one cleanup intent. */
export function cleanupJobId(input: NewCleanupJobInput): string {
  validateNewCleanupJobInput(input);
  const binding = JSON.stringify([
    input.sourceOperationId,
    input.world,
    input.queue,
    input.jobType,
    input.partition ?? null,
  ]);
  return createHash("sha256").update(binding, "utf8").digest("hex");
}

/** Builds an initial pending job document for a trusted producer. */
export function newCleanupJobData(
  input: NewCleanupJobInput,
  createdAt: Timestamp,
): CleanupJobData {
  validateNewCleanupJobInput(input);
  return Object.freeze({
    jobType: input.jobType,
    sourceOperationId: input.sourceOperationId,
    entityType: input.entityType,
    entityId: input.entityId,
    revision: input.revision,
    world: input.world,
    status: "pending",
    cursor: null,
    attemptCount: 0,
    leaseUntil: null,
    nextAttemptAt: createdAt,
    lastErrorCode: null,
    createdAt,
    updatedAt: createdAt,
    completedAt: null,
    expireAt: null,
  });
}

/** Returns the fixed local path for a queue job. */
export function cleanupJobPath(
  queue: CleanupJobQueue,
  jobId: string,
): string {
  requireQueue(queue);
  requirePattern(jobId, "jobId", VALUE_PATTERN);
  return `cleanupQueues/${queue}/jobs/${jobId}`;
}

/** Parses a server-owned cleanup document and enforces state invariants. */
export function parseCleanupJob(
  value: unknown,
  expectedWorld?: string,
): CleanupJobData {
  const data = requireRecord(value);
  if (Object.keys(data).length !== JOB_FIELDS.size ||
      [...JOB_FIELDS].some((field) => !(field in data))) {
    throw new Error("Cleanup job fields are invalid.");
  }

  const status = requireStatus(data.status);
  const createdAt = requireTimestamp(data.createdAt, "createdAt");
  const updatedAt = requireTimestamp(data.updatedAt, "updatedAt");
  const leaseUntil = requireNullableTimestamp(data.leaseUntil, "leaseUntil");
  const nextAttemptAt = requireNullableTimestamp(
    data.nextAttemptAt,
    "nextAttemptAt",
  );
  const completedAt = requireNullableTimestamp(data.completedAt, "completedAt");
  const expireAt = requireNullableTimestamp(data.expireAt, "expireAt");
  const world = requireStoredPattern(data.world, "world", VALUE_PATTERN);
  if (expectedWorld !== undefined && world !== expectedWorld) {
    throw new Error("Cleanup job world does not match its database route.");
  }
  if (updatedAt.toMillis() < createdAt.toMillis()) {
    throw new Error("Cleanup job timestamps are invalid.");
  }

  if (status === "pending" &&
      (leaseUntil !== null || nextAttemptAt === null ||
       completedAt !== null || expireAt !== null)) {
    throw new Error("Pending cleanup job fields are invalid.");
  }
  if (status === "running" &&
      (leaseUntil === null || nextAttemptAt !== null ||
       completedAt !== null || expireAt !== null)) {
    throw new Error("Running cleanup job fields are invalid.");
  }
  if (status === "complete" &&
      (leaseUntil !== null || nextAttemptAt !== null ||
       completedAt === null || expireAt === null ||
       completedAt.toMillis() < createdAt.toMillis() ||
       expireAt.toMillis() < completedAt.toMillis())) {
    throw new Error("Completed cleanup job fields are invalid.");
  }

  return Object.freeze({
    jobType: requireStoredPattern(data.jobType, "jobType", JOB_TYPE_PATTERN),
    sourceOperationId: requireStoredPattern(
      data.sourceOperationId,
      "sourceOperationId",
      VALUE_PATTERN,
    ),
    entityType: requireStoredPattern(
      data.entityType,
      "entityType",
      VALUE_PATTERN,
    ),
    entityId: requireStoredPattern(data.entityId, "entityId", VALUE_PATTERN),
    revision: requirePositiveSafeInteger(data.revision, "revision"),
    world,
    status,
    cursor: requireCursor(data.cursor),
    attemptCount: requireNonNegativeSafeInteger(
      data.attemptCount,
      "attemptCount",
    ),
    leaseUntil,
    nextAttemptAt,
    lastErrorCode: requireNullableErrorCode(data.lastErrorCode),
    createdAt,
    updatedAt,
    completedAt,
    expireAt,
  });
}

/** Processes bounded cleanup batches and durably checkpoints progress. */
export async function processCleanupJob(
  world: string,
  queue: CleanupJobQueue,
  jobId: string,
  runtime: CleanupRuntime,
): Promise<CleanupJobProcessResult> {
  assertWorld(runtime.catalog, world);
  const firestore = runtime.firestore.forWorld(world);
  const reference = firestore.doc(cleanupJobPath(queue, jobId));
  const now = runtime.now ?? Timestamp.now;
  const claimed = await claimCleanupJob(reference, world, now());
  if (claimed === undefined) {
    const snapshot = await reference.get();
    if (!snapshot.exists) {
      return {jobId, status: "missing", processed: false};
    }
    return {
      jobId,
      status: parseCleanupJob(snapshot.data(), world).status,
      processed: false,
    };
  }

  let current = claimed;
  try {
    const handler = runtime.handlers.require(queue, claimed.job.jobType);
    for (let batch = 0; batch < CLEANUP_JOB_MAX_BATCHES_PER_RUN; batch += 1) {
      const result = await handler.processBatch({
        queue,
        firestore,
        jobId,
        job: current.job,
        bucket: queue === "storage" ?
          runtime.buckets?.forWorld(world) :
          undefined,
      });
      current = await checkpointCleanupJob(current, result, now());
      if (current.job.status === "complete") {
        return {jobId, status: "complete", processed: true};
      }
    }
    await releaseCleanupJob(current, now());
    return {jobId, status: "pending", processed: true};
  } catch (error) {
    await retryCleanupJob(
      current,
      now(),
      cleanupErrorCode(error),
      runtime.random?.() ?? Math.random(),
    );
    return {jobId, status: "pending", processed: true};
  }
}

/** Returns a retry delay using the approved backoff sequence and jitter. */
export function cleanupRetryDelayMillis(
  attemptCount: number,
  jitterUnit: number,
): number {
  if (!Number.isSafeInteger(attemptCount) || attemptCount <= 0) {
    throw new Error("Cleanup attempt count must be positive.");
  }
  if (!Number.isFinite(jitterUnit) || jitterUnit < 0 || jitterUnit > 1) {
    throw new Error("Cleanup retry jitter must be between zero and one.");
  }
  const schedule = [
    10 * 60 * 1000,
    30 * 60 * 1000,
    2 * 60 * 60 * 1000,
    6 * 60 * 60 * 1000,
  ];
  const base = schedule[attemptCount - 1] ?? 24 * 60 * 60 * 1000;
  return Math.round(base * (0.9 + jitterUnit * 0.2));
}

/** Derives operational attention without adding another persisted state. */
export function deriveCleanupJobAttention(
  job: CleanupJobData,
  now: Timestamp,
): CleanupJobAttention {
  if (job.status === "complete") return "none";
  const age = Math.max(0, now.toMillis() - job.createdAt.toMillis());
  if (age >= CLEANUP_JOB_CRITICAL_AFTER_MILLIS) return "critical";
  return age >= CLEANUP_JOB_WARNING_AFTER_MILLIS ? "warning" : "none";
}

/** Claims a due job and increments its fencing attempt. */
async function claimCleanupJob(
  reference: DocumentReference,
  world: string,
  now: Timestamp,
): Promise<ClaimedCleanupJob | undefined> {
  return reference.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) return undefined;
    const job = parseCleanupJob(snapshot.data(), world);
    let due = false;
    if (job.status === "pending" && job.nextAttemptAt !== null) {
      due = job.nextAttemptAt.toMillis() <= now.toMillis();
    } else if (job.status === "running" && job.leaseUntil !== null) {
      due = job.leaseUntil.toMillis() <= now.toMillis();
    }
    if (!due) return undefined;

    const attempt = job.attemptCount + 1;
    const leaseUntil = Timestamp.fromMillis(
      now.toMillis() + CLEANUP_JOB_LEASE_MILLIS,
    );
    const running = parseCleanupJob({
      ...job,
      status: "running",
      attemptCount: attempt,
      leaseUntil,
      nextAttemptAt: null,
      updatedAt: now,
    }, world);
    transaction.set(reference, {...running});
    return {reference, job: running, attempt};
  });
}

/** Persists a batch cursor or transitions a claimed job to complete. */
async function checkpointCleanupJob(
  claimed: ClaimedCleanupJob,
  result: CleanupBatchResult,
  now: Timestamp,
): Promise<ClaimedCleanupJob> {
  return claimed.reference.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(claimed.reference);
    if (!snapshot.exists) throw new Error("Claimed cleanup job disappeared.");
    const current = parseCleanupJob(snapshot.data(), claimed.job.world);
    assertLeaseOwner(current, claimed.attempt);

    if (result.complete) {
      const completedAt = now;
      const complete = parseCleanupJob({
        ...current,
        status: "complete",
        leaseUntil: null,
        nextAttemptAt: null,
        lastErrorCode: null,
        updatedAt: completedAt,
        completedAt,
        expireAt: Timestamp.fromMillis(
          completedAt.toMillis() +
            GLOBAL_OPERATION_TERMINAL_RETENTION_MILLIS,
        ),
      }, current.world);
      transaction.set(claimed.reference, {...complete});
      return {...claimed, job: complete};
    }

    requireCursorProgress(current.cursor, result.cursor);
    const checkpointed = parseCleanupJob({
      ...current,
      cursor: result.cursor,
      leaseUntil: Timestamp.fromMillis(
        now.toMillis() + CLEANUP_JOB_LEASE_MILLIS,
      ),
      lastErrorCode: null,
      updatedAt: now,
    }, current.world);
    transaction.set(claimed.reference, {...checkpointed});
    return {...claimed, job: checkpointed};
  });
}

/** Releases a bounded invocation for immediate scheduled continuation. */
async function releaseCleanupJob(
  claimed: ClaimedCleanupJob,
  now: Timestamp,
): Promise<void> {
  await claimed.reference.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(claimed.reference);
    if (!snapshot.exists) throw new Error("Claimed cleanup job disappeared.");
    const current = parseCleanupJob(snapshot.data(), claimed.job.world);
    assertLeaseOwner(current, claimed.attempt);
    transaction.update(claimed.reference, {
      status: "pending",
      leaseUntil: null,
      nextAttemptAt: now,
      updatedAt: now,
    });
  });
}

/** Records a retryable failure without creating a terminal failed state. */
async function retryCleanupJob(
  claimed: ClaimedCleanupJob,
  now: Timestamp,
  errorCode: string,
  jitterUnit: number,
): Promise<void> {
  await claimed.reference.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(claimed.reference);
    if (!snapshot.exists) throw new Error("Claimed cleanup job disappeared.");
    const current = parseCleanupJob(snapshot.data(), claimed.job.world);
    assertLeaseOwner(current, claimed.attempt);
    transaction.update(claimed.reference, {
      status: "pending",
      leaseUntil: null,
      nextAttemptAt: Timestamp.fromMillis(
        now.toMillis() +
          cleanupRetryDelayMillis(current.attemptCount, jitterUnit),
      ),
      lastErrorCode: errorCode,
      updatedAt: now,
    });
  });
}

/** Validates fields supplied by a trusted cleanup producer. */
function validateNewCleanupJobInput(input: NewCleanupJobInput): void {
  requireQueue(input.queue);
  requirePattern(input.sourceOperationId, "sourceOperationId", VALUE_PATTERN);
  requirePattern(input.entityType, "entityType", VALUE_PATTERN);
  requirePattern(input.entityId, "entityId", VALUE_PATTERN);
  requirePattern(input.world, "world", VALUE_PATTERN);
  requirePattern(input.jobType, "jobType", JOB_TYPE_PATTERN);
  requirePositiveSafeInteger(input.revision, "revision");
  if (input.partition !== undefined) {
    requirePattern(input.partition, "partition", VALUE_PATTERN);
  }
}

/** Rejects a database route outside the trusted catalog. */
function assertWorld(catalog: WorldCatalog, worldId: string): void {
  if (!catalog.worlds.some((world) => world.worldId === worldId)) {
    throw new Error(`Unknown cleanup world: ${worldId}.`);
  }
}

/** Applies the attempt counter as a stale-worker fencing token. */
function assertLeaseOwner(job: CleanupJobData, attempt: number): void {
  if (job.status !== "running" || job.attemptCount !== attempt) {
    throw new Error("Cleanup job lease was superseded.");
  }
}

/** Requires each incomplete batch to advance its durable cursor. */
function requireCursorProgress(previous: string | null, next: string): void {
  if (next.length === 0 ||
      next.length > MAX_CURSOR_LENGTH ||
      next === previous) {
    throw new Error("Cleanup handler returned an invalid cursor checkpoint.");
  }
}

/** Extracts only a bounded structured error code for job storage. */
function cleanupErrorCode(error: unknown): string {
  if (typeof error === "object" && error !== null && "code" in error) {
    const code = String((error as {code: unknown}).code);
    if (ERROR_CODE_PATTERN.test(code)) return code;
  }
  return "unknown";
}

/** Creates the registry key for one queue-specific handler. */
function handlerKey(queue: CleanupJobQueue, jobType: string): string {
  return `${queue}:${jobType}`;
}

/** Validates a cleanup queue name. */
function requireQueue(value: unknown): asserts value is CleanupJobQueue {
  if (value !== "firestore" && value !== "storage") {
    throw new Error("Cleanup queue is invalid.");
  }
}

/** Requires an ordinary object for persisted parsing. */
function requireRecord(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("Cleanup job must be an object.");
  }
  return value as Record<string, unknown>;
}

/** Validates a cleanup job status. */
function requireStatus(value: unknown): CleanupJobStatus {
  if (value !== "pending" && value !== "running" && value !== "complete") {
    throw new Error("Cleanup job status is invalid.");
  }
  return value;
}

/** Validates a bounded string field. */
function requirePattern(
  value: unknown,
  field: string,
  pattern: RegExp,
): string {
  if (typeof value !== "string" || !pattern.test(value)) {
    throw new Error(`Cleanup ${field} is invalid.`);
  }
  return value;
}

/** Validates a bounded persisted string field. */
function requireStoredPattern(
  value: unknown,
  field: string,
  pattern: RegExp,
): string {
  return requirePattern(value, field, pattern);
}

/** Validates a positive safe integer field. */
function requirePositiveSafeInteger(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`Cleanup ${field} is invalid.`);
  }
  return value;
}

/** Validates a non-negative safe integer field. */
function requireNonNegativeSafeInteger(
  value: unknown,
  field: string,
): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw new Error(`Cleanup ${field} is invalid.`);
  }
  return value;
}

/** Validates a required Firestore timestamp. */
function requireTimestamp(value: unknown, field: string): Timestamp {
  if (!(value instanceof Timestamp)) {
    throw new Error(`Cleanup ${field} is invalid.`);
  }
  return value;
}

/** Validates an explicitly nullable Firestore timestamp. */
function requireNullableTimestamp(
  value: unknown,
  field: string,
): Timestamp | null {
  if (value === null) return null;
  return requireTimestamp(value, field);
}

/** Validates a bounded opaque handler cursor. */
function requireCursor(value: unknown): string | null {
  if (value === null) return null;
  if (typeof value !== "string" ||
      value.length === 0 || value.length > MAX_CURSOR_LENGTH) {
    throw new Error("Cleanup cursor is invalid.");
  }
  return value;
}

/** Validates a nullable structured error code. */
function requireNullableErrorCode(value: unknown): string | null {
  if (value === null) return null;
  return requireStoredPattern(value, "lastErrorCode", ERROR_CODE_PATTERN);
}
