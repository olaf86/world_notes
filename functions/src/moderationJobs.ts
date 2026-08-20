/* eslint-disable require-jsdoc, valid-jsdoc */

import {createHash} from "node:crypto";

import {
  DocumentReference,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

import {GLOBAL_OPERATION_TERMINAL_RETENTION_MILLIS} from "./globalOperations";
import {WorldFirestoreProvider} from "./platform/worldFirestoreProvider";
import {WorldCatalog} from "./platform/worldCatalog";

export const MODERATION_JOB_LEASE_MILLIS = 5 * 60 * 1000;
export const MODERATION_JOB_RECONCILE_BATCH_SIZE = 50;
export const MODERATION_JOB_WARNING_AFTER_MILLIS = 15 * 60 * 1000;
export const MODERATION_JOB_CRITICAL_AFTER_MILLIS = 24 * 60 * 60 * 1000;

const JOB_ID_PATTERN = /^[0-9a-f]{64}$/;
const JOB_TYPE_PATTERN = /^[a-z][A-Za-z0-9]{0,63}$/;
const INPUT_HASH_PATTERN = /^[0-9a-f]{64}$/;
const WORLD_PATTERN = /^[a-z][A-Za-z0-9]{1,31}$/;
const ERROR_CODE_PATTERN = /^[A-Za-z0-9_.:/-]{1,128}$/;
const MAX_TARGET_PATH_BYTES = 1_024;
const JOB_FIELDS = new Set([
  "jobId",
  "jobType",
  "targetPath",
  "inputHash",
  "world",
  "status",
  "attemptCount",
  "leaseUntil",
  "nextAttemptAt",
  "lastErrorCode",
  "createdAt",
  "updatedAt",
  "completedAt",
  "expireAt",
]);

export type ModerationJobStatus = "pending" | "running" | "complete";
export type ModerationJobAttention = "none" | "warning" | "critical";

export interface ModerationJobData {
  readonly jobId: string;
  readonly jobType: string;
  readonly targetPath: string;
  readonly inputHash: string;
  readonly world: string;
  readonly status: ModerationJobStatus;
  readonly attemptCount: number;
  readonly leaseUntil: Timestamp | null;
  readonly nextAttemptAt: Timestamp | null;
  readonly lastErrorCode: string | null;
  readonly createdAt: Timestamp;
  readonly updatedAt: Timestamp;
  readonly completedAt: Timestamp | null;
  readonly expireAt: Timestamp | null;
}

export interface NewModerationJobInput {
  readonly jobType: string;
  readonly targetPath: string;
  readonly inputHash: string;
  readonly world: string;
  readonly partition?: string;
}

export interface ModerationJobContext {
  readonly firestore: Firestore;
  readonly jobId: string;
  readonly job: ModerationJobData;
}

/** Owns provider evaluation and local finalization for one job type. */
export interface ModerationJobHandler {
  readonly jobType: string;
  process(context: ModerationJobContext): Promise<void>;
}

/** Immutable allowlist assigning one handler to each moderation job type. */
export class ModerationJobHandlerRegistry {
  private readonly handlers = new Map<string, ModerationJobHandler>();

  /** Creates a registry and rejects ambiguous handler ownership. */
  constructor(handlers: readonly ModerationJobHandler[]) {
    for (const handler of handlers) {
      requirePattern(handler.jobType, "jobType", JOB_TYPE_PATTERN);
      if (this.handlers.has(handler.jobType)) {
        throw new Error(`Duplicate moderation handler: ${handler.jobType}.`);
      }
      this.handlers.set(handler.jobType, handler);
    }
  }

  /** Returns the sole trusted handler for a moderation job type. */
  require(jobType: string): ModerationJobHandler {
    const handler = this.handlers.get(jobType);
    if (handler === undefined) {
      throw new Error(`No moderation handler is registered for ${jobType}.`);
    }
    return handler;
  }
}

export interface ModerationJobRuntime {
  readonly catalog: WorldCatalog;
  readonly firestore: WorldFirestoreProvider;
  readonly handlers: ModerationJobHandlerRegistry;
  readonly now?: () => Timestamp;
  readonly random?: () => number;
}

export interface ModerationJobProcessResult {
  readonly jobId: string;
  readonly status: ModerationJobStatus | "missing";
  readonly processed: boolean;
}

interface ClaimedModerationJob {
  readonly reference: DocumentReference;
  readonly job: ModerationJobData;
  readonly attempt: number;
}

/** Derives a stable job ID from the immutable moderation input identity. */
export function moderationJobId(input: NewModerationJobInput): string {
  validateNewModerationJobInput(input);
  const binding = JSON.stringify([
    input.world,
    input.jobType,
    input.targetPath,
    input.inputHash,
    input.partition ?? null,
  ]);
  return createHash("sha256").update(binding, "utf8").digest("hex");
}

/** Builds a pending server-owned moderation job document. */
export function newModerationJobData(
  input: NewModerationJobInput,
  createdAt: Timestamp,
): ModerationJobData {
  validateNewModerationJobInput(input);
  const jobId = moderationJobId(input);
  return Object.freeze({
    jobId,
    jobType: input.jobType,
    targetPath: input.targetPath,
    inputHash: input.inputHash,
    world: input.world,
    status: "pending",
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

/** Adds a moderation job to the same transaction as its pending content. */
export function enqueueModerationJob(
  transaction: Transaction,
  firestore: Firestore,
  input: NewModerationJobInput,
  createdAt: Timestamp,
): string {
  const data = newModerationJobData(input, createdAt);
  transaction.create(
    firestore.collection("moderationJobs").doc(data.jobId),
    {...data},
  );
  return data.jobId;
}

/** Parses persisted job data and enforces every lifecycle invariant. */
export function parseModerationJob(
  value: unknown,
  expectedJobId?: string,
  expectedWorld?: string,
): ModerationJobData {
  const data = requireRecord(value);
  if (Object.keys(data).length !== JOB_FIELDS.size ||
      [...JOB_FIELDS].some((field) => !(field in data))) {
    throw new Error("Moderation job fields are invalid.");
  }

  const jobId = requirePattern(data.jobId, "jobId", JOB_ID_PATTERN);
  if (expectedJobId !== undefined && jobId !== expectedJobId) {
    throw new Error("Moderation job ID does not match its document path.");
  }
  const world = requirePattern(data.world, "world", WORLD_PATTERN);
  if (expectedWorld !== undefined && world !== expectedWorld) {
    throw new Error("Moderation job world does not match its database route.");
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
  if (updatedAt.toMillis() < createdAt.toMillis()) {
    throw new Error("Moderation job timestamps are invalid.");
  }

  if (status === "pending" &&
      (leaseUntil !== null || nextAttemptAt === null ||
       completedAt !== null || expireAt !== null)) {
    throw new Error("Pending moderation job fields are invalid.");
  }
  if (status === "running" &&
      (leaseUntil === null || nextAttemptAt !== null ||
       completedAt !== null || expireAt !== null)) {
    throw new Error("Running moderation job fields are invalid.");
  }
  if (status === "complete" &&
      (leaseUntil !== null || nextAttemptAt !== null ||
       completedAt === null || expireAt === null ||
       completedAt.toMillis() < createdAt.toMillis() ||
       expireAt.toMillis() < completedAt.toMillis())) {
    throw new Error("Completed moderation job fields are invalid.");
  }

  return Object.freeze({
    jobId,
    jobType: requirePattern(data.jobType, "jobType", JOB_TYPE_PATTERN),
    targetPath: requireTargetPath(data.targetPath),
    inputHash: requirePattern(data.inputHash, "inputHash", INPUT_HASH_PATTERN),
    world,
    status,
    attemptCount: requireNonNegativeInteger(data.attemptCount, "attemptCount"),
    leaseUntil,
    nextAttemptAt,
    lastErrorCode: requireNullableErrorCode(data.lastErrorCode),
    createdAt,
    updatedAt,
    completedAt,
    expireAt,
  });
}

/**
 * Claims and processes one due job. Failures always remain retryable.
 */
export async function processModerationJob(
  world: string,
  jobId: string,
  runtime: ModerationJobRuntime,
): Promise<ModerationJobProcessResult> {
  assertWorld(runtime.catalog, world);
  requirePattern(jobId, "jobId", JOB_ID_PATTERN);
  const firestore = runtime.firestore.forWorld(world);
  const reference = firestore.collection("moderationJobs").doc(jobId);
  const now = runtime.now ?? Timestamp.now;
  const claimed = await claimModerationJob(reference, world, now());
  if (claimed === undefined) {
    const snapshot = await reference.get();
    if (!snapshot.exists) return {jobId, status: "missing", processed: false};
    return {
      jobId,
      status: parseModerationJob(snapshot.data(), jobId, world).status,
      processed: false,
    };
  }

  try {
    const handler = runtime.handlers.require(claimed.job.jobType);
    await handler.process({firestore, jobId, job: claimed.job});
    await completeModerationJob(claimed, now());
    return {jobId, status: "complete", processed: true};
  } catch (error) {
    await retryModerationJob(
      claimed,
      now(),
      moderationErrorCode(error),
      runtime.random?.() ?? Math.random(),
    );
    return {jobId, status: "pending", processed: true};
  }
}

/** Returns retry delay with jitter; moderation work is never abandoned. */
export function moderationRetryDelayMillis(
  attemptCount: number,
  jitterUnit: number,
): number {
  if (!Number.isSafeInteger(attemptCount) || attemptCount <= 0) {
    throw new Error("Moderation attempt count must be positive.");
  }
  if (!Number.isFinite(jitterUnit) || jitterUnit < 0 || jitterUnit > 1) {
    throw new Error("Moderation retry jitter must be between zero and one.");
  }
  const schedule = [
    60 * 1000,
    5 * 60 * 1000,
    15 * 60 * 1000,
    60 * 60 * 1000,
    6 * 60 * 60 * 1000,
  ];
  const base = schedule[attemptCount - 1] ?? 24 * 60 * 60 * 1000;
  return Math.round(base * (0.9 + jitterUnit * 0.2));
}

/** Derives operational attention without another persisted status. */
export function deriveModerationJobAttention(
  job: ModerationJobData,
  now: Timestamp,
): ModerationJobAttention {
  if (job.status === "complete") return "none";
  const age = Math.max(0, now.toMillis() - job.createdAt.toMillis());
  if (age >= MODERATION_JOB_CRITICAL_AFTER_MILLIS) return "critical";
  return age >= MODERATION_JOB_WARNING_AFTER_MILLIS ? "warning" : "none";
}

async function claimModerationJob(
  reference: DocumentReference,
  world: string,
  now: Timestamp,
): Promise<ClaimedModerationJob | undefined> {
  return reference.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) return undefined;
    const job = parseModerationJob(snapshot.data(), reference.id, world);
    const due = job.status === "pending" ?
      job.nextAttemptAt !== null &&
        job.nextAttemptAt.toMillis() <= now.toMillis() :
      job.status === "running" && job.leaseUntil !== null &&
        job.leaseUntil.toMillis() <= now.toMillis();
    if (!due) return undefined;

    const attempt = job.attemptCount + 1;
    const running = parseModerationJob({
      ...job,
      status: "running",
      attemptCount: attempt,
      leaseUntil: Timestamp.fromMillis(
        now.toMillis() + MODERATION_JOB_LEASE_MILLIS,
      ),
      nextAttemptAt: null,
      updatedAt: now,
    }, reference.id, world);
    transaction.set(reference, {...running});
    return {reference, job: running, attempt};
  });
}

async function completeModerationJob(
  claimed: ClaimedModerationJob,
  now: Timestamp,
): Promise<void> {
  await claimed.reference.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(claimed.reference);
    if (!snapshot.exists) {
      throw new Error("Claimed moderation job disappeared.");
    }
    const current = parseModerationJob(
      snapshot.data(),
      claimed.reference.id,
      claimed.job.world,
    );
    assertAttemptOwner(current, claimed.attempt);
    transaction.update(claimed.reference, {
      status: "complete",
      leaseUntil: null,
      nextAttemptAt: null,
      lastErrorCode: null,
      updatedAt: now,
      completedAt: now,
      expireAt: Timestamp.fromMillis(
        now.toMillis() + GLOBAL_OPERATION_TERMINAL_RETENTION_MILLIS,
      ),
    });
  });
}

async function retryModerationJob(
  claimed: ClaimedModerationJob,
  now: Timestamp,
  errorCode: string,
  jitterUnit: number,
): Promise<void> {
  await claimed.reference.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(claimed.reference);
    if (!snapshot.exists) {
      throw new Error("Claimed moderation job disappeared.");
    }
    const current = parseModerationJob(
      snapshot.data(),
      claimed.reference.id,
      claimed.job.world,
    );
    assertAttemptOwner(current, claimed.attempt);
    transaction.update(claimed.reference, {
      status: "pending",
      leaseUntil: null,
      nextAttemptAt: Timestamp.fromMillis(
        now.toMillis() + moderationRetryDelayMillis(
          current.attemptCount,
          jitterUnit,
        ),
      ),
      lastErrorCode: errorCode,
      updatedAt: now,
    });
  });
}

function validateNewModerationJobInput(input: NewModerationJobInput): void {
  requirePattern(input.jobType, "jobType", JOB_TYPE_PATTERN);
  requireTargetPath(input.targetPath);
  requirePattern(input.inputHash, "inputHash", INPUT_HASH_PATTERN);
  requirePattern(input.world, "world", WORLD_PATTERN);
  if (input.partition !== undefined) {
    requirePattern(input.partition, "partition", ERROR_CODE_PATTERN);
  }
}

function assertWorld(catalog: WorldCatalog, worldId: string): void {
  if (!catalog.worlds.some((world) => world.worldId === worldId)) {
    throw new Error(`Unknown moderation world: ${worldId}.`);
  }
}

function assertAttemptOwner(job: ModerationJobData, attempt: number): void {
  if (job.status !== "running" || job.attemptCount !== attempt) {
    throw new Error("Moderation job lease was superseded.");
  }
}

function moderationErrorCode(error: unknown): string {
  if (typeof error === "object" && error !== null && "code" in error) {
    const code = String((error as {code: unknown}).code);
    if (ERROR_CODE_PATTERN.test(code)) return code;
  }
  return "unknown";
}

function requireRecord(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("Moderation job must be an object.");
  }
  return value as Record<string, unknown>;
}

function requireStatus(value: unknown): ModerationJobStatus {
  if (value !== "pending" && value !== "running" && value !== "complete") {
    throw new Error("Moderation job status is invalid.");
  }
  return value;
}

function requirePattern(
  value: unknown,
  field: string,
  pattern: RegExp,
): string {
  if (typeof value !== "string" || !pattern.test(value)) {
    throw new Error(`Moderation ${field} is invalid.`);
  }
  return value;
}

function requireTargetPath(value: unknown): string {
  if (typeof value !== "string" || value.length === 0 ||
      Buffer.byteLength(value, "utf8") > MAX_TARGET_PATH_BYTES ||
      value.startsWith("/") || value.endsWith("/") ||
      value.split("/").some((segment) =>
        segment.length === 0 || segment === "." || segment === "..")) {
    throw new Error("Moderation targetPath is invalid.");
  }
  return value;
}

function requireNonNegativeInteger(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw new Error(`Moderation ${field} is invalid.`);
  }
  return value;
}

function requireTimestamp(value: unknown, field: string): Timestamp {
  if (!(value instanceof Timestamp)) {
    throw new Error(`Moderation ${field} is invalid.`);
  }
  return value;
}

function requireNullableTimestamp(
  value: unknown,
  field: string,
): Timestamp | null {
  if (value === null) return null;
  return requireTimestamp(value, field);
}

function requireNullableErrorCode(value: unknown): string | null {
  if (value === null) return null;
  return requirePattern(value, "lastErrorCode", ERROR_CODE_PATTERN);
}
