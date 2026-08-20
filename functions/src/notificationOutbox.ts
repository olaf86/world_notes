/* eslint-disable valid-jsdoc */

import {createHash} from "node:crypto";

import {
  DocumentReference,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";

import {GLOBAL_OPERATION_TERMINAL_RETENTION_MILLIS} from "./globalOperations";
import {WorldFirestoreProvider} from "./platform/worldFirestoreProvider";
import {WorldCatalog} from "./platform/worldCatalog";

export const NOTIFICATION_LEASE_MILLIS = 5 * 60 * 1000;
export const NOTIFICATION_RECONCILE_BATCH_SIZE = 50;
export const NOTIFICATION_MAX_RECIPIENTS = 100;
export const NOTIFICATION_MAX_LIFETIME_MILLIS = 7 * 24 * 60 * 60 * 1000;

const TYPE_PATTERN = /^[a-z][A-Za-z0-9]{0,63}$/;
const VALUE_PATTERN = /^[^/\s]{1,256}$/;
const ERROR_CODE_PATTERN = /^[A-Za-z0-9_.:/-]{1,128}$/;
const EVENT_ID_PATTERN = /^[0-9a-f]{64}$/;
// Application envelope limit. Firestore's 6 KiB document-name limit applies
// to the fully qualified UTF-8 name, not this relative source path.
const MAX_SOURCE_PATH_UTF8_BYTES = 1_024;
const EVENT_FIELDS = new Set([
  "eventId",
  "eventType",
  "ownerWorld",
  "sourceWorld",
  "entityType",
  "entityId",
  "sourcePath",
  "recipientUids",
  "recipientResults",
  "status",
  "attemptCount",
  "leaseUntil",
  "nextAttemptAt",
  "lastErrorCode",
  "createdAt",
  "updatedAt",
  "expiresAt",
  "completedAt",
  "expireAt",
]);

export type NotificationEventStatus =
  "pending" | "running" | "complete" | "skipped" | "expired";
export type NotificationRecipientStatus = "pending" | "complete" | "skipped";
export type FcmErrorDisposition =
  "deleteToken" | "retry" | "deploymentFault" | "payloadFault";

export interface NotificationOutboxData {
  readonly eventId: string;
  readonly eventType: string;
  readonly ownerWorld: string;
  readonly sourceWorld: string;
  readonly entityType: string;
  readonly entityId: string;
  readonly sourcePath: string;
  readonly recipientUids: readonly string[];
  readonly recipientResults: Readonly<
    Record<string, NotificationRecipientStatus>
  >;
  readonly status: NotificationEventStatus;
  readonly attemptCount: number;
  readonly leaseUntil: Timestamp | null;
  readonly nextAttemptAt: Timestamp | null;
  readonly lastErrorCode: string | null;
  readonly createdAt: Timestamp;
  readonly updatedAt: Timestamp;
  readonly expiresAt: Timestamp;
  readonly completedAt: Timestamp | null;
  readonly expireAt: Timestamp | null;
}

export interface NotificationEventIdInput {
  readonly sourceEventId: string;
  readonly ownerWorld: string;
  readonly eventType: string;
  readonly partition?: string;
}

export interface NewNotificationOutboxInput extends NotificationEventIdInput {
  readonly eventId: string;
  readonly sourceWorld: string;
  readonly entityType: string;
  readonly entityId: string;
  readonly sourcePath: string;
  readonly recipientUids: readonly string[];
  readonly expiresAt: Timestamp;
}

export interface NotificationDeliveryContext {
  readonly firestore: Firestore;
  readonly event: NotificationOutboxData;
}

export interface NotificationDeliveryResult {
  readonly recipientResults: Readonly<
    Record<string, NotificationRecipientStatus>
  >;
  readonly lastErrorCode?: string;
}

/** Owns delivery for one trusted notification event type. */
export interface NotificationDeliveryHandler {
  readonly eventType: string;
  deliver(
    context: NotificationDeliveryContext,
  ): Promise<NotificationDeliveryResult>;
}

/** Immutable event-type allowlist for notification delivery. */
export class NotificationDeliveryHandlerRegistry {
  private readonly handlers = new Map<string, NotificationDeliveryHandler>();

  /** Creates a registry and rejects ambiguous handler ownership. */
  constructor(handlers: readonly NotificationDeliveryHandler[]) {
    for (const handler of handlers) {
      requirePattern(handler.eventType, "eventType", TYPE_PATTERN);
      if (this.handlers.has(handler.eventType)) {
        throw new Error(
          `Duplicate notification handler: ${handler.eventType}.`,
        );
      }
      this.handlers.set(handler.eventType, handler);
    }
  }

  /** Returns the sole handler trusted for an event type. */
  require(eventType: string): NotificationDeliveryHandler {
    const handler = this.handlers.get(eventType);
    if (handler === undefined) {
      throw new Error(
        `No notification handler is registered for ${eventType}.`,
      );
    }
    return handler;
  }
}

export interface NotificationOutboxRuntime {
  readonly catalog: WorldCatalog;
  readonly firestore: WorldFirestoreProvider;
  readonly handlers: NotificationDeliveryHandlerRegistry;
  readonly now?: () => Timestamp;
  readonly random?: () => number;
}

export interface NotificationProcessResult {
  readonly eventId: string;
  readonly status: NotificationEventStatus | "missing";
  readonly processed: boolean;
}

interface ClaimedNotificationEvent {
  readonly reference: DocumentReference;
  readonly event: NotificationOutboxData;
  readonly attempt: number;
}

/** Derives one globally stable notification event ID. */
export function notificationEventId(input: NotificationEventIdInput): string {
  validateEventIdInput(input);
  const binding = JSON.stringify([
    input.sourceEventId,
    input.ownerWorld,
    input.eventType,
    input.partition ?? null,
  ]);
  return createHash("sha256").update(binding, "utf8").digest("hex");
}

/** Builds a pending server-owned notification outbox event. */
export function newNotificationOutboxData(
  input: NewNotificationOutboxInput,
  createdAt: Timestamp,
): NotificationOutboxData {
  validateNewEventInput(input, createdAt);
  const recipients = Object.freeze([...input.recipientUids]);
  const recipientResults = Object.freeze(Object.fromEntries(
    recipients.map((uid) => [uid, "pending" as const]),
  ));
  return Object.freeze({
    eventId: input.eventId,
    eventType: input.eventType,
    ownerWorld: input.ownerWorld,
    sourceWorld: input.sourceWorld,
    entityType: input.entityType,
    entityId: input.entityId,
    sourcePath: input.sourcePath,
    recipientUids: recipients,
    recipientResults,
    status: "pending",
    attemptCount: 0,
    leaseUntil: null,
    nextAttemptAt: createdAt,
    lastErrorCode: null,
    createdAt,
    updatedAt: createdAt,
    expiresAt: input.expiresAt,
    completedAt: null,
    expireAt: null,
  });
}

/** Parses one persisted outbox event and enforces lifecycle invariants. */
export function parseNotificationOutbox(
  value: unknown,
  expectedEventId?: string,
  expectedWorld?: string,
): NotificationOutboxData {
  const data = requireRecord(value, "notification event");
  if (Object.keys(data).length !== EVENT_FIELDS.size ||
      [...EVENT_FIELDS].some((field) => !(field in data))) {
    throw new Error("Notification event fields are invalid.");
  }

  const eventId = requirePattern(data.eventId, "eventId", EVENT_ID_PATTERN);
  if (expectedEventId !== undefined && eventId !== expectedEventId) {
    throw new Error("Notification event ID does not match its document path.");
  }
  const ownerWorld = requirePattern(
    data.ownerWorld,
    "ownerWorld",
    VALUE_PATTERN,
  );
  if (expectedWorld !== undefined && ownerWorld !== expectedWorld) {
    throw new Error(
      "Notification owner world does not match its database route.",
    );
  }
  const recipientUids = requireRecipients(data.recipientUids);
  const recipientResults = requireRecipientResults(
    data.recipientResults,
    recipientUids,
  );
  const status = requireEventStatus(data.status);
  const createdAt = requireTimestamp(data.createdAt, "createdAt");
  const updatedAt = requireTimestamp(data.updatedAt, "updatedAt");
  const expiresAt = requireTimestamp(data.expiresAt, "expiresAt");
  const leaseUntil = requireNullableTimestamp(data.leaseUntil, "leaseUntil");
  const nextAttemptAt = requireNullableTimestamp(
    data.nextAttemptAt,
    "nextAttemptAt",
  );
  const completedAt = requireNullableTimestamp(
    data.completedAt,
    "completedAt",
  );
  const expireAt = requireNullableTimestamp(data.expireAt, "expireAt");
  if (updatedAt.toMillis() < createdAt.toMillis() ||
      expiresAt.toMillis() <= createdAt.toMillis()) {
    throw new Error("Notification event timestamps are invalid.");
  }

  const terminal = isTerminalNotificationStatus(status);
  if (status === "pending" &&
      (leaseUntil !== null || nextAttemptAt === null || terminal ||
       completedAt !== null || expireAt !== null)) {
    throw new Error("Pending notification event fields are invalid.");
  }
  if (status === "running" &&
      (leaseUntil === null || nextAttemptAt !== null ||
       completedAt !== null || expireAt !== null)) {
    throw new Error("Running notification event fields are invalid.");
  }
  if (terminal &&
      (leaseUntil !== null || nextAttemptAt !== null ||
       completedAt === null || expireAt === null ||
       expireAt.toMillis() < completedAt.toMillis())) {
    throw new Error("Terminal notification event fields are invalid.");
  }
  const hasPendingRecipient = Object.values(recipientResults).includes(
    "pending",
  );
  if (terminal && hasPendingRecipient) {
    throw new Error("Terminal notification event has pending recipients.");
  }
  if (!terminal && !hasPendingRecipient) {
    throw new Error("Active notification event has no pending recipients.");
  }

  return Object.freeze({
    eventId,
    eventType: requirePattern(data.eventType, "eventType", TYPE_PATTERN),
    ownerWorld,
    sourceWorld: requirePattern(data.sourceWorld, "sourceWorld", VALUE_PATTERN),
    entityType: requirePattern(data.entityType, "entityType", VALUE_PATTERN),
    entityId: requirePattern(data.entityId, "entityId", VALUE_PATTERN),
    sourcePath: requireDocumentPath(data.sourcePath),
    recipientUids: Object.freeze(recipientUids),
    recipientResults: Object.freeze(recipientResults),
    status,
    attemptCount: requireNonNegativeInteger(data.attemptCount, "attemptCount"),
    leaseUntil,
    nextAttemptAt,
    lastErrorCode: requireNullableErrorCode(data.lastErrorCode),
    createdAt,
    updatedAt,
    expiresAt,
    completedAt,
    expireAt,
  });
}

/** Claims and delivers one due notification event. */
export async function processNotificationOutboxEvent(
  world: string,
  eventId: string,
  runtime: NotificationOutboxRuntime,
): Promise<NotificationProcessResult> {
  assertWorld(runtime.catalog, world);
  requirePattern(eventId, "eventId", EVENT_ID_PATTERN);
  const firestore = runtime.firestore.forWorld(world);
  const reference = firestore.collection("notificationOutbox").doc(eventId);
  const now = runtime.now ?? Timestamp.now;
  const claimed = await claimNotificationEvent(reference, world, now());
  if (claimed === undefined) {
    const snapshot = await reference.get();
    if (!snapshot.exists) return {eventId, status: "missing", processed: false};
    return {
      eventId,
      status: parseNotificationOutbox(snapshot.data(), eventId, world).status,
      processed: false,
    };
  }
  if (claimed.event.status === "expired") {
    return {eventId, status: "expired", processed: true};
  }

  try {
    const handler = runtime.handlers.require(claimed.event.eventType);
    const result = await handler.deliver({firestore, event: claimed.event});
    const status = await finalizeNotificationAttempt(
      claimed,
      result,
      now(),
      runtime.random?.() ?? Math.random(),
    );
    return {eventId, status, processed: true};
  } catch (error) {
    await retryNotificationEvent(
      claimed,
      now(),
      notificationErrorCode(error),
      runtime.random?.() ?? Math.random(),
    );
    return {eventId, status: "pending", processed: true};
  }
}

/** Returns the next retry time without scheduling past event expiry. */
export function notificationRetryAt(
  attemptCount: number,
  failedAt: Timestamp,
  expiresAt: Timestamp,
  jitterUnit: number,
): Timestamp {
  if (!Number.isSafeInteger(attemptCount) || attemptCount <= 0) {
    throw new Error("Notification attempt count must be positive.");
  }
  if (!Number.isFinite(jitterUnit) || jitterUnit < 0 || jitterUnit > 1) {
    throw new Error("Notification retry jitter must be between zero and one.");
  }
  const schedule = [
    60 * 1000,
    5 * 60 * 1000,
    30 * 60 * 1000,
    2 * 60 * 60 * 1000,
    6 * 60 * 60 * 1000,
  ];
  const finalDue = expiresAt.toMillis() - 5 * 60 * 1000;
  const base = schedule[attemptCount - 1];
  const candidate = base === undefined ?
    finalDue :
    failedAt.toMillis() + Math.round(base * (0.9 + jitterUnit * 0.2));
  const bounded = Math.min(candidate, finalDue);
  return Timestamp.fromMillis(
    bounded > failedAt.toMillis() ? bounded : expiresAt.toMillis(),
  );
}

/** Classifies an FCM result without deleting tokens on deployment faults. */
export function classifyFcmError(code: string): FcmErrorDisposition {
  if (code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token") {
    return "deleteToken";
  }
  if (DEPLOYMENT_FCM_CODES.has(code)) return "deploymentFault";
  if (PAYLOAD_FCM_CODES.has(code)) return "payloadFault";
  return "retry";
}

const DEPLOYMENT_FCM_CODES: ReadonlySet<string> = new Set([
  "messaging/authentication-error",
  "messaging/invalid-apns-credentials",
  "messaging/invalid-credential",
  "messaging/mismatched-credential",
  "messaging/sender-id-mismatch",
  "messaging/third-party-auth-error",
]);
const PAYLOAD_FCM_CODES: ReadonlySet<string> = new Set([
  "messaging/invalid-argument",
  "messaging/invalid-data-payload-key",
  "messaging/invalid-options",
  "messaging/invalid-payload",
  "messaging/payload-size-limit-exceeded",
]);

/** Claims a due event or expires it atomically before delivery. */
async function claimNotificationEvent(
  reference: DocumentReference,
  world: string,
  now: Timestamp,
): Promise<ClaimedNotificationEvent | undefined> {
  return reference.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) return undefined;
    const event = parseNotificationOutbox(snapshot.data(), reference.id, world);
    if (isTerminalNotificationStatus(event.status)) return undefined;
    const due = event.status === "pending" ?
      event.nextAttemptAt !== null &&
        event.nextAttemptAt.toMillis() <= now.toMillis() :
      event.leaseUntil !== null &&
        event.leaseUntil.toMillis() <= now.toMillis();
    if (!due) return undefined;

    if (event.expiresAt.toMillis() <= now.toMillis()) {
      const recipientResults = mapPendingRecipients(event, "skipped");
      const expired = terminalEvent(event, "expired", recipientResults, now);
      transaction.set(reference, {...expired});
      return {reference, event: expired, attempt: event.attemptCount};
    }

    const attempt = event.attemptCount + 1;
    const running = parseNotificationOutbox({
      ...event,
      status: "running",
      attemptCount: attempt,
      leaseUntil: Timestamp.fromMillis(
        now.toMillis() + NOTIFICATION_LEASE_MILLIS,
      ),
      nextAttemptAt: null,
      updatedAt: now,
    }, reference.id, world);
    transaction.set(reference, {...running});
    return {reference, event: running, attempt};
  });
}

/** Applies recipient outcomes and completes or reschedules the event. */
async function finalizeNotificationAttempt(
  claimed: ClaimedNotificationEvent,
  result: NotificationDeliveryResult,
  now: Timestamp,
  jitterUnit: number,
): Promise<NotificationEventStatus> {
  return claimed.reference.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(claimed.reference);
    if (!snapshot.exists) throw new Error("Claimed notification disappeared.");
    const current = parseNotificationOutbox(
      snapshot.data(),
      claimed.reference.id,
      claimed.event.ownerWorld,
    );
    assertAttemptOwner(current, claimed.attempt);
    const recipientResults = mergeRecipientResults(current, result);
    if (!Object.values(recipientResults).includes("pending")) {
      const status = Object.values(recipientResults).includes("complete") ?
        "complete" : "skipped";
      const terminal = terminalEvent(current, status, recipientResults, now);
      transaction.set(claimed.reference, {...terminal});
      return status;
    }
    const lastErrorCode = requirePattern(
      result.lastErrorCode ?? "delivery-retry",
      "lastErrorCode",
      ERROR_CODE_PATTERN,
    );
    transaction.update(claimed.reference, {
      recipientResults,
      status: "pending",
      leaseUntil: null,
      nextAttemptAt: notificationRetryAt(
        current.attemptCount,
        now,
        current.expiresAt,
        jitterUnit,
      ),
      lastErrorCode,
      updatedAt: now,
    });
    return "pending";
  });
}

/** Records a retryable worker failure while preserving recipient progress. */
async function retryNotificationEvent(
  claimed: ClaimedNotificationEvent,
  now: Timestamp,
  errorCode: string,
  jitterUnit: number,
): Promise<void> {
  await claimed.reference.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(claimed.reference);
    if (!snapshot.exists) throw new Error("Claimed notification disappeared.");
    const current = parseNotificationOutbox(
      snapshot.data(),
      claimed.reference.id,
      claimed.event.ownerWorld,
    );
    assertAttemptOwner(current, claimed.attempt);
    transaction.update(claimed.reference, {
      status: "pending",
      leaseUntil: null,
      nextAttemptAt: notificationRetryAt(
        current.attemptCount,
        now,
        current.expiresAt,
        jitterUnit,
      ),
      lastErrorCode: errorCode,
      updatedAt: now,
    });
  });
}

/** Creates a terminal event with the shared retention deadline. */
function terminalEvent(
  event: NotificationOutboxData,
  status: "complete" | "skipped" | "expired",
  recipientResults: Readonly<Record<string, NotificationRecipientStatus>>,
  now: Timestamp,
): NotificationOutboxData {
  return parseNotificationOutbox({
    ...event,
    recipientResults,
    status,
    leaseUntil: null,
    nextAttemptAt: null,
    lastErrorCode: null,
    updatedAt: now,
    completedAt: now,
    expireAt: Timestamp.fromMillis(
      now.toMillis() + GLOBAL_OPERATION_TERMINAL_RETENTION_MILLIS,
    ),
  }, event.eventId, event.ownerWorld);
}

/** Validates and merges exactly the recipients still pending delivery. */
function mergeRecipientResults(
  event: NotificationOutboxData,
  result: NotificationDeliveryResult,
): Readonly<Record<string, NotificationRecipientStatus>> {
  const pending = event.recipientUids.filter(
    (uid) => event.recipientResults[uid] === "pending",
  );
  if (Object.keys(result.recipientResults).length !== pending.length ||
      pending.some((uid) => !(uid in result.recipientResults))) {
    throw new Error("Notification handler recipient results are incomplete.");
  }
  const merged = {...event.recipientResults};
  for (const uid of pending) {
    merged[uid] = requireRecipientStatus(result.recipientResults[uid]);
  }
  return Object.freeze(merged);
}

/** Applies one terminal result to every still-pending recipient. */
function mapPendingRecipients(
  event: NotificationOutboxData,
  status: "skipped",
): Readonly<Record<string, NotificationRecipientStatus>> {
  return Object.freeze(Object.fromEntries(event.recipientUids.map((uid) => [
    uid,
    event.recipientResults[uid] === "pending" ?
      status :
      event.recipientResults[uid],
  ])));
}

/** Validates event-ID inputs used before source transaction creation. */
function validateEventIdInput(input: NotificationEventIdInput): void {
  requirePattern(input.sourceEventId, "sourceEventId", VALUE_PATTERN);
  requirePattern(input.ownerWorld, "ownerWorld", VALUE_PATTERN);
  requirePattern(input.eventType, "eventType", TYPE_PATTERN);
  if (input.partition !== undefined) {
    requirePattern(input.partition, "partition", VALUE_PATTERN);
  }
}

/** Validates a new outbox event and its bounded recipient snapshot. */
function validateNewEventInput(
  input: NewNotificationOutboxInput,
  createdAt: Timestamp,
): void {
  validateEventIdInput(input);
  requirePattern(input.eventId, "eventId", EVENT_ID_PATTERN);
  if (notificationEventId(input) !== input.eventId) {
    throw new Error("Notification event ID does not match its source binding.");
  }
  requirePattern(input.sourceWorld, "sourceWorld", VALUE_PATTERN);
  requirePattern(input.entityType, "entityType", VALUE_PATTERN);
  requirePattern(input.entityId, "entityId", VALUE_PATTERN);
  requireDocumentPath(input.sourcePath);
  requireRecipients(input.recipientUids);
  const lifetime = input.expiresAt.toMillis() - createdAt.toMillis();
  if (lifetime <= 0 || lifetime > NOTIFICATION_MAX_LIFETIME_MILLIS) {
    throw new Error("Notification event lifetime is invalid.");
  }
}

/** Rejects a route outside the trusted world catalog. */
function assertWorld(catalog: WorldCatalog, worldId: string): void {
  if (!catalog.worlds.some((world) => world.worldId === worldId)) {
    throw new Error(`Unknown notification world: ${worldId}.`);
  }
}

/** Uses attemptCount as a stale-worker fencing token. */
function assertAttemptOwner(
  event: NotificationOutboxData,
  attempt: number,
): void {
  if (event.status !== "running" || event.attemptCount !== attempt) {
    throw new Error("Notification event lease was superseded.");
  }
}

/** Returns true for all terminal outbox states. */
function isTerminalNotificationStatus(
  status: NotificationEventStatus,
): boolean {
  return status === "complete" || status === "skipped" || status === "expired";
}

/** Extracts a bounded error code without persisting provider messages. */
function notificationErrorCode(error: unknown): string {
  if (typeof error === "object" && error !== null && "code" in error) {
    const code = String((error as {code: unknown}).code);
    if (ERROR_CODE_PATTERN.test(code)) return code;
  }
  return "unknown";
}

/** Requires a plain object. */
function requireRecord(
  value: unknown,
  field: string,
): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(`${field} must be an object.`);
  }
  return value as Record<string, unknown>;
}

/** Validates one bounded string. */
function requirePattern(
  value: unknown,
  field: string,
  pattern: RegExp,
): string {
  if (typeof value !== "string" || !pattern.test(value)) {
    throw new Error(`Notification ${field} is invalid.`);
  }
  return value;
}

/** Validates a bounded even-segment Firestore document path. */
function requireDocumentPath(value: unknown): string {
  if (typeof value !== "string" ||
      Buffer.byteLength(value, "utf8") > MAX_SOURCE_PATH_UTF8_BYTES) {
    throw new Error("Notification sourcePath is invalid.");
  }
  const segments = value.split("/");
  if (segments.length < 2 || segments.length % 2 !== 0 ||
      segments.some((segment) => segment.length === 0)) {
    throw new Error("Notification sourcePath is invalid.");
  }
  return value;
}

/** Validates an event status. */
function requireEventStatus(value: unknown): NotificationEventStatus {
  if (value !== "pending" && value !== "running" && value !== "complete" &&
      value !== "skipped" && value !== "expired") {
    throw new Error("Notification status is invalid.");
  }
  return value;
}

/** Validates one recipient result. */
function requireRecipientStatus(value: unknown): NotificationRecipientStatus {
  if (value !== "pending" && value !== "complete" && value !== "skipped") {
    throw new Error("Notification recipient status is invalid.");
  }
  return value;
}

/** Validates a unique bounded recipient snapshot. */
function requireRecipients(value: unknown): string[] {
  if (!Array.isArray(value) || value.length === 0 ||
      value.length > NOTIFICATION_MAX_RECIPIENTS) {
    throw new Error("Notification recipients are invalid.");
  }
  const recipients = value.map((uid) =>
    requirePattern(uid, "recipientUid", VALUE_PATTERN));
  if (new Set(recipients).size !== recipients.length) {
    throw new Error("Notification recipients contain duplicates.");
  }
  return recipients;
}

/** Validates recipient state keys against the immutable snapshot. */
function requireRecipientResults(
  value: unknown,
  recipients: readonly string[],
): Record<string, NotificationRecipientStatus> {
  const results = requireRecord(value, "recipientResults");
  if (Object.keys(results).length !== recipients.length ||
      recipients.some((uid) => !(uid in results))) {
    throw new Error("Notification recipient results are invalid.");
  }
  return Object.fromEntries(recipients.map((uid) => [
    uid,
    requireRecipientStatus(results[uid]),
  ]));
}

/** Validates a non-negative safe integer. */
function requireNonNegativeInteger(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw new Error(`Notification ${field} is invalid.`);
  }
  return value;
}

/** Validates a Firestore timestamp. */
function requireTimestamp(value: unknown, field: string): Timestamp {
  if (!(value instanceof Timestamp)) {
    throw new Error(`Notification ${field} is invalid.`);
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

/** Validates a nullable structured error code. */
function requireNullableErrorCode(value: unknown): string | null {
  if (value === null) return null;
  return requirePattern(value, "lastErrorCode", ERROR_CODE_PATTERN);
}
