/* eslint-disable valid-jsdoc */

import {createHash, randomBytes} from "node:crypto";

import {
  DocumentReference,
  DocumentSnapshot,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

import {
  WORLD_CATALOG,
  WorldCatalog,
} from "./platform/worldCatalog";

const OPERATION_ID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const OPERATION_TYPE_PATTERN = /^[a-z][A-Za-z0-9]{0,63}$/;
const PATH_SEGMENT_PATTERN = /^[^/\s]{1,128}$/;
const PAYLOAD_HASH_PATTERN = /^[0-9a-f]{64}$/;
export const GLOBAL_OPERATION_TERMINAL_RETENTION_MILLIS =
  30 * 24 * 60 * 60 * 1000;
const MAX_CANONICAL_DEPTH = 12;
const MAX_CANONICAL_ITEMS = 100;
const MAX_CANONICAL_STRING_LENGTH = 16_384;
const MAX_CANONICAL_PAYLOAD_LENGTH = 65_536;
const MAX_REQUIRED_WORLDS = 32;

const OPERATION_REQUIRED_FIELDS = new Set([
  "operationId",
  "operationType",
  "entityId",
  "revision",
  "authorityWorld",
  "ownerUid",
  "payloadHash",
  "status",
  "acceptedAt",
  "worldCatalogVersion",
  "requiredWorlds",
  "worldAcks",
  "createdAt",
  "updatedAt",
]);
const OPERATION_OPTIONAL_FIELDS = new Set([
  "completedAt",
  "failureCode",
  "expireAt",
]);

export type GlobalOperationStatus = "pending" | "complete" | "failed";

/** Trusted policy selecting destinations for one global command type. */
export const GLOBAL_COMMAND_SCOPE = Object.freeze({
  authorityOnly: "authorityOnly",
  allActiveWorlds: "allActiveWorlds",
} as const);

export type GlobalCommandScope =
  typeof GLOBAL_COMMAND_SCOPE[keyof typeof GLOBAL_COMMAND_SCOPE];

export interface GlobalWorldAck {
  readonly revision: number;
  readonly acknowledgedAt: Timestamp;
}

export interface GlobalOperationData {
  readonly operationId: string;
  readonly operationType: string;
  readonly entityId: string;
  readonly revision: number;
  readonly authorityWorld: string;
  readonly ownerUid: string;
  readonly payloadHash: string;
  readonly status: GlobalOperationStatus;
  readonly acceptedAt: Timestamp;
  readonly worldCatalogVersion: number;
  readonly requiredWorlds: readonly string[];
  readonly worldAcks: Readonly<Record<string, GlobalWorldAck>>;
  readonly createdAt: Timestamp;
  readonly updatedAt: Timestamp;
  readonly completedAt?: Timestamp;
  readonly failureCode?: string;
  readonly expireAt?: Timestamp;
}

export interface GlobalCommandMutationContext {
  readonly transaction: Transaction;
  readonly entity: DocumentSnapshot;
  readonly revision: number;
  readonly acceptedAt: Timestamp;
}

export interface ExecuteGlobalCommandInput {
  readonly firestore: Firestore;
  readonly authorityWorld: string;
  readonly ownerUid: string;
  readonly operationId: unknown;
  readonly operationType: string;
  readonly entityId: string;
  readonly payload: unknown;
  readonly entityRef: DocumentReference;
  readonly revisionField?: string;
  readonly scope: GlobalCommandScope;
  readonly catalog?: WorldCatalog;
  readonly mutate: (
    context: GlobalCommandMutationContext,
  ) => void | Promise<void>;
}

export interface GlobalCommandResult {
  readonly accepted: boolean;
  readonly replayed: boolean;
  readonly authorityWorld: string;
  readonly operationId: string;
  readonly revision: number;
  readonly status: GlobalOperationStatus;
}

/** A client operation ID was already bound to another logical command. */
export class GlobalOperationBindingError extends Error {
  /** Creates a stable conflict error without exposing stored operation data. */
  constructor() {
    super("Operation ID is already bound to another command.");
    this.name = "GlobalOperationBindingError";
  }
}

/** A caller supplied an invalid global command envelope field. */
export class GlobalOperationValidationError extends Error {
  /** Creates a validation error suitable for mapping to invalid-argument. */
  constructor(message: string) {
    super(message);
    this.name = "GlobalOperationValidationError";
  }
}

/** Creates a lowercase UUID v7 for trusted server-originated operations. */
export function newGlobalOperationId(nowMillis = Date.now()): string {
  if (!Number.isSafeInteger(nowMillis) || nowMillis < 0 ||
      nowMillis > 0xffffffffffff) {
    throw new GlobalOperationValidationError(
      "Operation timestamp is outside the UUID v7 range.",
    );
  }
  const bytes = randomBytes(16);
  let timestamp = nowMillis;
  for (let index = 5; index >= 0; index -= 1) {
    bytes[index] = timestamp & 0xff;
    timestamp = Math.floor(timestamp / 256);
  }
  bytes[6] = 0x70 | (bytes[6] & 0x0f);
  bytes[8] = 0x80 | (bytes[8] & 0x3f);
  const hex = bytes.toString("hex");
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20),
  ].join("-");
}

/** Derives a retry-stable child UUID v7 from a persisted parent operation. */
export function derivedGlobalOperationId(
  parentOperationId: string,
  binding: string,
): string {
  requireOperationId(parentOperationId);
  if (binding.length === 0 || binding.length > 1_024) {
    throw new GlobalOperationValidationError(
      "Derived operation binding is invalid.",
    );
  }
  const parentHex = parentOperationId.replace(/-/g, "");
  const timestampHex = parentHex.slice(0, 12);
  const digest = createHash("sha256")
    .update(parentOperationId, "utf8")
    .update("\0", "utf8")
    .update(binding, "utf8")
    .digest("hex");
  const bytes = Buffer.from(`${timestampHex}${digest.slice(0, 20)}`, "hex");
  bytes[6] = 0x70 | (bytes[6] & 0x0f);
  bytes[8] = 0x80 | (bytes[8] & 0x3f);
  const hex = bytes.toString("hex");
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20),
  ].join("-");
}

/**
 * Commits an entity mutation and its durable operation work item atomically.
 */
export async function executeGlobalCommand(
  input: ExecuteGlobalCommandInput,
): Promise<GlobalCommandResult> {
  const operationId = requireOperationId(input.operationId);
  requirePattern(
    input.operationType,
    "operationType",
    OPERATION_TYPE_PATTERN,
  );
  requirePattern(input.entityId, "entityId", PATH_SEGMENT_PATTERN);
  requirePattern(input.ownerUid, "ownerUid", PATH_SEGMENT_PATTERN);
  requirePattern(
    input.authorityWorld,
    "authorityWorld",
    PATH_SEGMENT_PATTERN,
  );
  requireRevisionField(input.revisionField ?? "revision");
  assertSameDatabase(input.firestore, input.entityRef);

  const catalog = input.catalog ?? WORLD_CATALOG;
  const requiredWorlds = snapshotRequiredWorlds(
    catalog,
    input.authorityWorld,
    input.scope,
  );
  const payloadHash = canonicalPayloadHash(input.payload);
  const operationRef = input.firestore
    .collection("globalOperations")
    .doc(operationId);

  return input.firestore.runTransaction(async (transaction) => {
    const existing = await transaction.get(operationRef);
    if (existing.exists) {
      return replayExistingOperation(existing, {
        operationId,
        operationType: input.operationType,
        entityId: input.entityId,
        authorityWorld: input.authorityWorld,
        ownerUid: input.ownerUid,
        payloadHash,
      });
    }

    const entity = await transaction.get(input.entityRef);
    const revision = nextEntityRevision(
      entity,
      input.revisionField ?? "revision",
    );
    const acceptedAt = Timestamp.now();
    await input.mutate({transaction, entity, revision, acceptedAt});

    const worldAcks: Record<string, GlobalWorldAck> = {
      [input.authorityWorld]: {revision, acknowledgedAt: acceptedAt},
    };
    const complete = requiredWorlds.every((world) => world in worldAcks);
    const operation: GlobalOperationData = {
      operationId,
      operationType: input.operationType,
      entityId: input.entityId,
      revision,
      authorityWorld: input.authorityWorld,
      ownerUid: input.ownerUid,
      payloadHash,
      status: complete ? "complete" : "pending",
      acceptedAt,
      worldCatalogVersion: catalog.catalogVersion,
      requiredWorlds,
      worldAcks,
      createdAt: acceptedAt,
      updatedAt: acceptedAt,
      ...(complete ? globalOperationTerminalFields(acceptedAt) : {}),
    };
    transaction.create(operationRef, operation);

    return {
      accepted: true,
      replayed: false,
      authorityWorld: input.authorityWorld,
      operationId,
      revision,
      status: operation.status,
    };
  });
}

/** Returns a canonical SHA-256 hash without persisting the command payload. */
export function canonicalPayloadHash(payload: unknown): string {
  const canonical = canonicalize(payload, 0);
  if (canonical.length > MAX_CANONICAL_PAYLOAD_LENGTH) {
    throw new GlobalOperationValidationError("Command payload is too large.");
  }
  return createHash("sha256").update(canonical, "utf8").digest("hex");
}

/** Validates and returns the client-generated UUID v7 operation ID. */
export function requireOperationId(value: unknown): string {
  if (typeof value !== "string" || !OPERATION_ID_PATTERN.test(value)) {
    throw new GlobalOperationValidationError(
      "operationId must be a lowercase UUID v7.",
    );
  }
  return value;
}

/** Returns the next safe positive revision for one authority entity. */
export function nextEntityRevision(
  snapshot: DocumentSnapshot,
  revisionField = "revision",
): number {
  requireRevisionField(revisionField);
  const current = snapshot.get(revisionField);
  if (current === undefined) return 1;
  if (typeof current !== "number" ||
      !Number.isSafeInteger(current) ||
      current < 0 ||
      current >= Number.MAX_SAFE_INTEGER) {
    throw new Error(`Invalid authority revision at ${snapshot.ref.path}.`);
  }
  return current + 1;
}

/** Creates a deletion marker that cannot be superseded by an older event. */
export function revisionedTombstone(
  revision: number,
  deletedAt: Timestamp,
): Readonly<{revision: number; isDeleted: true; deletedAt: Timestamp}> {
  if (!Number.isSafeInteger(revision) || revision <= 0) {
    throw new GlobalOperationValidationError(
      "Tombstone revision must be a positive safe integer.",
    );
  }
  return Object.freeze({revision, isDeleted: true, deletedAt});
}

/** Snapshots trusted destination membership for this operation version. */
export function snapshotRequiredWorlds(
  catalog: WorldCatalog,
  authorityWorld: string,
  scope: GlobalCommandScope,
): readonly string[] {
  const activeWorlds = catalog.worlds
    .filter((world) => world.catalogState !== "provisioning")
    .map((world) => world.worldId);
  if (!activeWorlds.includes(authorityWorld)) {
    throw new GlobalOperationValidationError(
      "Authority world is not active in the catalog.",
    );
  }
  if (scope === GLOBAL_COMMAND_SCOPE.authorityOnly) {
    return Object.freeze([authorityWorld]);
  }
  if (scope !== GLOBAL_COMMAND_SCOPE.allActiveWorlds) {
    throw new GlobalOperationValidationError("Unsupported command scope.");
  }
  return Object.freeze([
    authorityWorld,
    ...activeWorlds.filter((world) => world !== authorityWorld),
  ]);
}

/** Parses and validates a trusted-server global operation document. */
export function parseGlobalOperation(
  value: unknown,
  expectedOperationId?: string,
): GlobalOperationData {
  const data = requireRecord(value, "global operation");
  const keys = Object.keys(data);
  if (![...OPERATION_REQUIRED_FIELDS].every((field) => field in data) ||
      keys.some((field) =>
        !OPERATION_REQUIRED_FIELDS.has(field) &&
        !OPERATION_OPTIONAL_FIELDS.has(field))) {
    throw new Error("Global operation fields are invalid.");
  }

  const operationId = requireStoredPattern(
    data.operationId,
    "operationId",
    OPERATION_ID_PATTERN,
  );
  if (expectedOperationId !== undefined &&
      operationId !== expectedOperationId) {
    throw new Error("Global operation ID does not match its document path.");
  }
  const operationType = requireStoredPattern(
    data.operationType,
    "operationType",
    OPERATION_TYPE_PATTERN,
  );
  const entityId = requireStoredPattern(
    data.entityId,
    "entityId",
    PATH_SEGMENT_PATTERN,
  );
  const revision = requirePositiveSafeInteger(data.revision, "revision");
  const authorityWorld = requireStoredPattern(
    data.authorityWorld,
    "authorityWorld",
    PATH_SEGMENT_PATTERN,
  );
  const ownerUid = requireStoredPattern(
    data.ownerUid,
    "ownerUid",
    PATH_SEGMENT_PATTERN,
  );
  const payloadHash = requireStoredPattern(
    data.payloadHash,
    "payloadHash",
    PAYLOAD_HASH_PATTERN,
  );
  const status = requireOperationStatus(data.status);
  const acceptedAt = requireTimestamp(data.acceptedAt, "acceptedAt");
  const worldCatalogVersion = requirePositiveSafeInteger(
    data.worldCatalogVersion,
    "worldCatalogVersion",
  );
  const requiredWorlds = requireWorldList(data.requiredWorlds);
  if (!requiredWorlds.includes(authorityWorld)) {
    throw new Error("requiredWorlds must contain authorityWorld.");
  }
  const worldAcks = requireWorldAcks(
    data.worldAcks,
    requiredWorlds,
    revision,
  );
  if (!(authorityWorld in worldAcks)) {
    throw new Error("worldAcks must contain the authority acknowledgement.");
  }
  const createdAt = requireTimestamp(data.createdAt, "createdAt");
  const updatedAt = requireTimestamp(data.updatedAt, "updatedAt");
  const completedAt = optionalTimestamp(data.completedAt, "completedAt");
  const expireAt = optionalTimestamp(data.expireAt, "expireAt");
  const failureCode = optionalFailureCode(data.failureCode);
  const allAcknowledged = requiredWorlds.every((world) => world in worldAcks);

  if (status === "pending" &&
      (completedAt !== undefined ||
       expireAt !== undefined ||
       failureCode !== undefined ||
       allAcknowledged)) {
    throw new Error("Pending global operation terminal fields are invalid.");
  }
  if (status === "complete" &&
      (!allAcknowledged ||
       completedAt === undefined ||
       expireAt === undefined ||
       failureCode !== undefined)) {
    throw new Error("Complete global operation fields are invalid.");
  }
  if (status === "failed" &&
      (completedAt === undefined ||
       expireAt === undefined ||
       failureCode === undefined)) {
    throw new Error("Failed global operation fields are invalid.");
  }
  if (completedAt !== undefined &&
      (completedAt.toMillis() < acceptedAt.toMillis() ||
       expireAt === undefined ||
       expireAt.toMillis() <= completedAt.toMillis())) {
    throw new Error("Global operation terminal timestamps are invalid.");
  }

  return Object.freeze({
    operationId,
    operationType,
    entityId,
    revision,
    authorityWorld,
    ownerUid,
    payloadHash,
    status,
    acceptedAt,
    worldCatalogVersion,
    requiredWorlds,
    worldAcks,
    createdAt,
    updatedAt,
    ...(completedAt === undefined ? {} : {completedAt}),
    ...(failureCode === undefined ? {} : {failureCode}),
    ...(expireAt === undefined ? {} : {expireAt}),
  });
}

interface OperationBinding {
  readonly operationId: string;
  readonly operationType: string;
  readonly entityId: string;
  readonly authorityWorld: string;
  readonly ownerUid: string;
  readonly payloadHash: string;
}

/** Validates an existing operation before returning an idempotent replay. */
function replayExistingOperation(
  snapshot: DocumentSnapshot,
  binding: OperationBinding,
): GlobalCommandResult {
  const operation = parseGlobalOperation(snapshot.data(), snapshot.id);
  const matches = Object.entries(binding).every(
    ([field, expected]) =>
      operation[field as keyof GlobalOperationData] === expected,
  );
  if (!matches) throw new GlobalOperationBindingError();
  return {
    accepted: operation.status !== "failed",
    replayed: true,
    authorityWorld: binding.authorityWorld,
    operationId: binding.operationId,
    revision: operation.revision,
    status: operation.status,
  };
}

/** Adds completion and TTL fields to a terminal operation. */
export function globalOperationTerminalFields(completedAt: Timestamp): {
  completedAt: Timestamp;
  expireAt: Timestamp;
} {
  return {
    completedAt,
    expireAt: Timestamp.fromMillis(
      completedAt.toMillis() + GLOBAL_OPERATION_TERMINAL_RETENTION_MILLIS,
    ),
  };
}

/** Deterministically encodes a bounded JSON-compatible value. */
function canonicalize(value: unknown, depth: number): string {
  if (depth > MAX_CANONICAL_DEPTH) {
    throw new GlobalOperationValidationError("Command payload is too deep.");
  }
  if (value === null) return "null";
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") {
    if (!Number.isFinite(value)) {
      throw new GlobalOperationValidationError(
        "Command payload contains a non-finite number.",
      );
    }
    return Object.is(value, -0) ? "0" : JSON.stringify(value);
  }
  if (typeof value === "string") {
    if (value.length > MAX_CANONICAL_STRING_LENGTH) {
      throw new GlobalOperationValidationError(
        "Command payload contains an oversized string.",
      );
    }
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    if (value.length > MAX_CANONICAL_ITEMS) {
      throw new GlobalOperationValidationError(
        "Command payload contains an oversized array.",
      );
    }
    return `[${value.map((item) => canonicalize(item, depth + 1)).join(",")}]`;
  }
  if (typeof value === "object") {
    const prototype = Object.getPrototypeOf(value);
    if (prototype !== Object.prototype && prototype !== null) {
      throw new GlobalOperationValidationError(
        "Command payload contains a non-JSON object.",
      );
    }
    const record = value as Record<string, unknown>;
    if (Reflect.ownKeys(record).some((key) => typeof key !== "string")) {
      throw new GlobalOperationValidationError(
        "Command payload contains a non-string field name.",
      );
    }
    const keys = Object.keys(record).sort();
    if (keys.length > MAX_CANONICAL_ITEMS) {
      throw new GlobalOperationValidationError(
        "Command payload contains an oversized object.",
      );
    }
    return `{${keys.map((key) => {
      if (key.length === 0 || key.length > 128) {
        throw new GlobalOperationValidationError(
          "Command payload contains an invalid field name.",
        );
      }
      return `${JSON.stringify(key)}:${canonicalize(record[key], depth + 1)}`;
    }).join(",")}}`;
  }
  throw new GlobalOperationValidationError(
    "Command payload must be JSON-compatible.",
  );
}

/** Confirms the entity reference belongs to the authority database. */
function assertSameDatabase(
  firestore: Firestore,
  entityRef: DocumentReference,
): void {
  if (entityRef.firestore.databaseId !== firestore.databaseId) {
    throw new GlobalOperationValidationError(
      "Authority entity belongs to another database.",
    );
  }
}

/** Validates one bounded identifier. */
function requirePattern(
  value: string,
  field: string,
  pattern: RegExp,
): void {
  if (!pattern.test(value)) {
    throw new GlobalOperationValidationError(`${field} is invalid.`);
  }
}

/** Prevents field-path injection through a configurable revision field. */
function requireRevisionField(value: string): void {
  if (!/^[a-z][A-Za-z0-9]{0,63}$/.test(value)) {
    throw new GlobalOperationValidationError("revisionField is invalid.");
  }
}

/** Reads a plain Firestore map. */
function requireRecord(
  value: unknown,
  field: string,
): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${field} must be a map.`);
  }
  return value as Record<string, unknown>;
}

/** Reads one stored string constrained by an application identifier pattern. */
function requireStoredPattern(
  value: unknown,
  field: string,
  pattern: RegExp,
): string {
  if (typeof value !== "string" || !pattern.test(value)) {
    throw new Error(`Global operation ${field} is invalid.`);
  }
  return value;
}

/** Reads a positive safe integer from persisted operation metadata. */
function requirePositiveSafeInteger(value: unknown, field: string): number {
  if (typeof value !== "number" ||
      !Number.isSafeInteger(value) ||
      value <= 0) {
    throw new Error(`Global operation ${field} is invalid.`);
  }
  return value;
}

/** Reads one supported operation status. */
function requireOperationStatus(value: unknown): GlobalOperationStatus {
  if (value !== "pending" && value !== "complete" && value !== "failed") {
    throw new Error("Global operation status is invalid.");
  }
  return value;
}

/** Reads a required Firestore timestamp. */
function requireTimestamp(value: unknown, field: string): Timestamp {
  if (!(value instanceof Timestamp)) {
    throw new Error(`Global operation ${field} is invalid.`);
  }
  return value;
}

/** Reads an optional Firestore timestamp. */
function optionalTimestamp(
  value: unknown,
  field: string,
): Timestamp | undefined {
  return value === undefined ? undefined : requireTimestamp(value, field);
}

/** Reads a bounded terminal failure code. */
function optionalFailureCode(value: unknown): string | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== "string" || !/^[a-z][a-z0-9-]{0,63}$/.test(value)) {
    throw new Error("Global operation failureCode is invalid.");
  }
  return value;
}

/** Reads a unique bounded list of trusted world IDs. */
function requireWorldList(value: unknown): readonly string[] {
  if (!Array.isArray(value) ||
      value.length === 0 ||
      value.length > MAX_REQUIRED_WORLDS) {
    throw new Error("Global operation requiredWorlds is invalid.");
  }
  const worlds = value.map((world) =>
    requireStoredPattern(world, "requiredWorld", PATH_SEGMENT_PATTERN));
  if (new Set(worlds).size !== worlds.length) {
    throw new Error("Global operation requiredWorlds contains duplicates.");
  }
  return Object.freeze(worlds);
}

/** Reads acknowledgement receipts scoped to required worlds. */
function requireWorldAcks(
  value: unknown,
  requiredWorlds: readonly string[],
  operationRevision: number,
): Readonly<Record<string, GlobalWorldAck>> {
  const raw = requireRecord(value, "worldAcks");
  const acks: Record<string, GlobalWorldAck> = {};
  for (const [world, rawAck] of Object.entries(raw)) {
    if (!requiredWorlds.includes(world)) {
      throw new Error("worldAcks contains a world outside requiredWorlds.");
    }
    const ack = requireRecord(rawAck, `worldAcks.${world}`);
    if (Object.keys(ack).length !== 2 ||
        !("revision" in ack) ||
        !("acknowledgedAt" in ack)) {
      throw new Error(`Global operation worldAcks.${world} is invalid.`);
    }
    const revision = requirePositiveSafeInteger(
      ack.revision,
      `worldAcks.${world}.revision`,
    );
    if (revision < operationRevision) {
      throw new Error("Global operation acknowledgement is stale.");
    }
    acks[world] = Object.freeze({
      revision,
      acknowledgedAt: requireTimestamp(
        ack.acknowledgedAt,
        `worldAcks.${world}.acknowledgedAt`,
      ),
    });
  }
  return Object.freeze(acks);
}
