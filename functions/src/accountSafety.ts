/* eslint-disable require-jsdoc, valid-jsdoc */

import {
  DocumentReference,
  DocumentSnapshot,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {
  GlobalReplicationApplyContext,
  GlobalReplicationFinalizeContext,
  GlobalReplicationHandler,
} from "./globalReplication";
import {
  executeGlobalCommand,
  GLOBAL_COMMAND_SCOPE,
  GlobalCommandResult,
  requireOperationId,
} from "./globalOperations";

export const APPLY_ACCOUNT_SAFETY_EVENT_OPERATION =
  "applyAccountSafetyEvent";
export const ADMIN_UPDATE_ACCOUNT_SAFETY_OPERATION =
  "adminUpdateAccountSafety";
export const ACCOUNT_SAFETY_WARNING_POINTS = 20;
export const ACCOUNT_SAFETY_RESTRICTION_POINTS = 60;
export const ACCOUNT_SAFETY_BAN_POINTS = 100;
export const ACCOUNT_SAFETY_HIDDEN_CONTENT_POINTS = 25;
export const ACCOUNT_SAFETY_MAX_POINTS = 100;
export const ACCOUNT_SAFETY_DECAY_GRACE_MILLIS =
  30 * 24 * 60 * 60 * 1000;
export const ACCOUNT_SAFETY_DECAY_INTERVAL_MILLIS =
  7 * 24 * 60 * 60 * 1000;
export const ACCOUNT_SAFETY_DECAY_POINTS = 6;
export const ACCOUNT_SAFETY_RESTRICTION_MILLIS =
  24 * 60 * 60 * 1000;
export const ACCOUNT_SAFETY_BAN_MILLIS =
  7 * 24 * 60 * 60 * 1000;
export const ACCOUNT_SAFETY_AUDIT_RETENTION_MILLIS =
  365 * 24 * 60 * 60 * 1000;

const MAX_UID_LENGTH = 128;
const MAX_EVENT_ID_LENGTH = 256;
const SAFETY_FIELDS = new Set([
  "revision",
  "violationPoints",
  "lastViolationAt",
  "nextPointDecayAt",
  "automatedRestrictedUntil",
  "automatedBannedUntil",
  "adminRestrictedUntil",
  "adminBannedUntil",
  "restrictedUntil",
  "bannedUntil",
  "isPermanentlyBanned",
  "authorityWorld",
  "updatedAt",
]);

export interface AccountSafetyProjection {
  readonly revision: number;
  readonly violationPoints: number;
  readonly lastViolationAt: Timestamp | null;
  readonly nextPointDecayAt: Timestamp | null;
  readonly automatedRestrictedUntil: Timestamp | null;
  readonly automatedBannedUntil: Timestamp | null;
  readonly adminRestrictedUntil: Timestamp | null;
  readonly adminBannedUntil: Timestamp | null;
  readonly restrictedUntil: Timestamp | null;
  readonly bannedUntil: Timestamp | null;
  readonly isPermanentlyBanned: boolean;
  readonly authorityWorld: string;
  readonly updatedAt: Timestamp;
}

export interface AccountSafetyDecayResult {
  readonly violationPoints: number;
  readonly nextPointDecayAt: Timestamp | null;
}

export interface ExecuteAccountSafetyEventInput {
  readonly firestore: Firestore;
  readonly authorityWorld: string;
  readonly uid: string;
  readonly operationId: unknown;
  readonly eventId: string;
  readonly points: number;
  readonly sourceWorld: string;
  readonly sourceType: string;
  readonly sourceEntityId: string;
}

export type AdminAccountSafetyAction =
  | {readonly type: "adjustPoints"; readonly delta: number}
  | {readonly type: "setRestriction"; readonly durationDays: 1 | 3 | 7}
  | {readonly type: "clearRestriction"}
  | {readonly type: "setBan"; readonly durationDays: 7 | 30}
  | {readonly type: "setPermanentBan"}
  | {readonly type: "clearBan"};

export interface ExecuteAdminAccountSafetyUpdateInput {
  readonly firestore: Firestore;
  readonly authorityWorld: string;
  readonly targetUid: string;
  readonly adminUid: string;
  readonly operationId: unknown;
  readonly action: AdminAccountSafetyAction;
  readonly reason: string;
  readonly reference: string | null;
}

export type AccountSafetyOperationFamily = "contentWrite" | "participation";
export type AccountSafetyDenialReason =
  "account-banned" | "posting-restricted" | null;

/** Replicates the complete local account-enforcement projection. */
export const accountSafetyReplicationHandler: GlobalReplicationHandler = {
  operationType: APPLY_ACCOUNT_SAFETY_EVENT_OPERATION,
  apply: replicateAccountSafety,
  finalize: finalizeAccountSafetyOperation,
};

/** Uses the same projection copier for audited administrator operations. */
export const adminAccountSafetyReplicationHandler: GlobalReplicationHandler = {
  operationType: ADMIN_UPDATE_ACCOUNT_SAFETY_OPERATION,
  apply: replicateAccountSafety,
  finalize: finalizeAccountSafetyOperation,
};

/** Returns the account-safety document for one trusted UID. */
export function accountSafetyRef(
  firestore: Firestore,
  uid: string,
): DocumentReference {
  requireUid(uid);
  return firestore.collection("accountSafety").doc(uid);
}

/** Builds the initial unrestricted authority state. */
export function initialAccountSafetyData(
  authorityWorld: string,
  now: Timestamp,
): AccountSafetyProjection {
  requireValue(authorityWorld, "authorityWorld");
  return Object.freeze({
    revision: 1,
    violationPoints: 0,
    lastViolationAt: null,
    nextPointDecayAt: null,
    automatedRestrictedUntil: null,
    automatedBannedUntil: null,
    adminRestrictedUntil: null,
    adminBannedUntil: null,
    restrictedUntil: null,
    bannedUntil: null,
    isPermanentlyBanned: false,
    authorityWorld,
    updatedAt: now,
  });
}

/** Parses an authority or mirror document and verifies effective fields. */
export function parseAccountSafetyProjection(
  snapshot: DocumentSnapshot,
  expectedAuthorityWorld?: string,
): AccountSafetyProjection {
  if (!snapshot.exists) {
    throw new Error("Account safety projection is missing.");
  }
  const data = snapshot.data();
  if (data === undefined ||
      Object.keys(data).length !== SAFETY_FIELDS.size ||
      [...SAFETY_FIELDS].some((field) => !(field in data))) {
    throw new Error("Account safety projection fields are invalid.");
  }
  const authorityWorld = requireValue(data.authorityWorld, "authorityWorld");
  if (expectedAuthorityWorld !== undefined &&
      authorityWorld !== expectedAuthorityWorld) {
    throw new Error("Account safety authority world is invalid.");
  }
  const projection: AccountSafetyProjection = Object.freeze({
    revision: requirePositiveInteger(data.revision, "revision"),
    violationPoints: requirePoints(data.violationPoints),
    lastViolationAt: requireNullableTimestamp(
      data.lastViolationAt,
      "lastViolationAt",
    ),
    nextPointDecayAt: requireNullableTimestamp(
      data.nextPointDecayAt,
      "nextPointDecayAt",
    ),
    automatedRestrictedUntil: requireNullableTimestamp(
      data.automatedRestrictedUntil,
      "automatedRestrictedUntil",
    ),
    automatedBannedUntil: requireNullableTimestamp(
      data.automatedBannedUntil,
      "automatedBannedUntil",
    ),
    adminRestrictedUntil: requireNullableTimestamp(
      data.adminRestrictedUntil,
      "adminRestrictedUntil",
    ),
    adminBannedUntil: requireNullableTimestamp(
      data.adminBannedUntil,
      "adminBannedUntil",
    ),
    restrictedUntil: requireNullableTimestamp(
      data.restrictedUntil,
      "restrictedUntil",
    ),
    bannedUntil: requireNullableTimestamp(data.bannedUntil, "bannedUntil"),
    isPermanentlyBanned: requireBoolean(
      data.isPermanentlyBanned,
      "isPermanentlyBanned",
    ),
    authorityWorld,
    updatedAt: requireTimestamp(data.updatedAt, "updatedAt"),
  });
  if (!sameTimestamp(
    projection.restrictedUntil,
    latestTimestamp(
      projection.automatedRestrictedUntil,
      projection.adminRestrictedUntil,
    ),
  ) || !sameTimestamp(
    projection.bannedUntil,
    latestTimestamp(
      projection.automatedBannedUntil,
      projection.adminBannedUntil,
    ),
  )) {
    throw new Error("Account safety effective enforcement is invalid.");
  }
  if (projection.violationPoints === 0 &&
      projection.nextPointDecayAt !== null) {
    throw new Error("Zero account safety points cannot have pending decay.");
  }
  return projection;
}

/** Applies every due six-point decay interval without scheduled writes. */
export function applyAccountSafetyDecay(
  currentPoints: number,
  nextPointDecayAt: Timestamp | null,
  now: Timestamp,
): AccountSafetyDecayResult {
  requirePoints(currentPoints);
  if (currentPoints === 0) {
    return Object.freeze({violationPoints: 0, nextPointDecayAt: null});
  }
  if (nextPointDecayAt === null ||
      now.toMillis() < nextPointDecayAt.toMillis()) {
    return Object.freeze({
      violationPoints: currentPoints,
      nextPointDecayAt,
    });
  }
  const intervals = Math.floor(
    (now.toMillis() - nextPointDecayAt.toMillis()) /
      ACCOUNT_SAFETY_DECAY_INTERVAL_MILLIS,
  ) + 1;
  const violationPoints = Math.max(
    0,
    currentPoints - intervals * ACCOUNT_SAFETY_DECAY_POINTS,
  );
  return Object.freeze({
    violationPoints,
    nextPointDecayAt: violationPoints === 0 ? null : Timestamp.fromMillis(
      nextPointDecayAt.toMillis() +
        intervals * ACCOUNT_SAFETY_DECAY_INTERVAL_MILLIS,
    ),
  });
}

/** Applies one deduplicated point-bearing event at the subject's home. */
export async function executeAccountSafetyEvent(
  input: ExecuteAccountSafetyEventInput,
): Promise<GlobalCommandResult> {
  const operationId = requireOperationId(input.operationId);
  requireUid(input.uid);
  requireEventId(input.eventId);
  requirePoints(input.points);
  requireValue(input.sourceWorld, "sourceWorld");
  requireValue(input.sourceType, "sourceType");
  requireValue(input.sourceEntityId, "sourceEntityId");
  const safetyRef = accountSafetyRef(input.firestore, input.uid);
  const homeRef = input.firestore.collection("userHomes").doc(input.uid);
  const receiptRef = safetyRef.collection("appliedEvents").doc(input.eventId);

  return executeGlobalCommand({
    firestore: input.firestore,
    authorityWorld: input.authorityWorld,
    ownerUid: input.uid,
    operationId,
    operationType: APPLY_ACCOUNT_SAFETY_EVENT_OPERATION,
    entityId: input.uid,
    payload: {
      eventId: input.eventId,
      points: input.points,
      sourceWorld: input.sourceWorld,
      sourceType: input.sourceType,
      sourceEntityId: input.sourceEntityId,
    },
    entityRef: safetyRef,
    scope: GLOBAL_COMMAND_SCOPE.allActiveWorlds,
    mutate: async ({transaction, entity, revision, acceptedAt}) => {
      const [home, receipt] = await Promise.all([
        transaction.get(homeRef),
        transaction.get(receiptRef),
      ]);
      if (!home.exists || home.get("world") !== input.authorityWorld) {
        throw new Error(
          "Account safety command used the wrong home authority.",
        );
      }
      if (receipt.exists) {
        throw new Error(
          "Account safety event receipt exists without operation.",
        );
      }
      const current = parseAccountSafetyProjection(
        entity,
        input.authorityWorld,
      );
      const decayed = applyAccountSafetyDecay(
        current.violationPoints,
        current.nextPointDecayAt,
        acceptedAt,
      );
      const points = Math.min(
        ACCOUNT_SAFETY_MAX_POINTS,
        decayed.violationPoints + input.points,
      );
      const pointBearing = input.points > 0;
      const nextPointDecayAt = pointBearing ? Timestamp.fromMillis(
        acceptedAt.toMillis() + ACCOUNT_SAFETY_DECAY_GRACE_MILLIS +
          ACCOUNT_SAFETY_DECAY_INTERVAL_MILLIS,
      ) : decayed.nextPointDecayAt;
      const automatedRestrictedUntil =
        pointBearing && points >= ACCOUNT_SAFETY_RESTRICTION_POINTS ?
          laterOf(
            current.automatedRestrictedUntil,
            Timestamp.fromMillis(
              acceptedAt.toMillis() + ACCOUNT_SAFETY_RESTRICTION_MILLIS,
            ),
          ) : current.automatedRestrictedUntil;
      const automatedBannedUntil =
        pointBearing && points >= ACCOUNT_SAFETY_BAN_POINTS ?
          laterOf(
            current.automatedBannedUntil,
            Timestamp.fromMillis(
              acceptedAt.toMillis() + ACCOUNT_SAFETY_BAN_MILLIS,
            ),
          ) : current.automatedBannedUntil;
      const next = {
        ...current,
        revision,
        violationPoints: points,
        lastViolationAt: pointBearing ? acceptedAt : current.lastViolationAt,
        nextPointDecayAt: points === 0 ? null : nextPointDecayAt,
        automatedRestrictedUntil,
        automatedBannedUntil,
        restrictedUntil: latestTimestamp(
          automatedRestrictedUntil,
          current.adminRestrictedUntil,
        ),
        bannedUntil: latestTimestamp(
          automatedBannedUntil,
          current.adminBannedUntil,
        ),
        updatedAt: acceptedAt,
      } satisfies AccountSafetyProjection;
      transaction.set(safetyRef, next);
      transaction.create(receiptRef, {
        eventId: input.eventId,
        operationId,
        revision,
        points: input.points,
        sourceWorld: input.sourceWorld,
        sourceType: input.sourceType,
        sourceEntityId: input.sourceEntityId,
        appliedAt: acceptedAt,
        expireAt: null,
      });
    },
  });
}

/** Applies one independently audited administrator safety command. */
export async function executeAdminAccountSafetyUpdate(
  input: ExecuteAdminAccountSafetyUpdateInput,
): Promise<GlobalCommandResult> {
  const operationId = requireOperationId(input.operationId);
  requireUid(input.targetUid);
  requireUid(input.adminUid);
  parseAdminAccountSafetyAction(input.action);
  const reason = requireTrimmedText(input.reason, "reason", 500);
  const reference = input.reference === null ? null :
    requireTrimmedText(input.reference, "reference", 256);
  const safetyRef = accountSafetyRef(input.firestore, input.targetUid);
  const homeRef = input.firestore
    .collection("userHomes")
    .doc(input.targetUid);
  const auditRef = safetyRef.collection("adminAudits").doc(operationId);

  return executeGlobalCommand({
    firestore: input.firestore,
    authorityWorld: input.authorityWorld,
    ownerUid: input.targetUid,
    operationId,
    operationType: ADMIN_UPDATE_ACCOUNT_SAFETY_OPERATION,
    entityId: input.targetUid,
    payload: {action: input.action, reason, reference},
    entityRef: safetyRef,
    scope: GLOBAL_COMMAND_SCOPE.allActiveWorlds,
    mutate: async ({transaction, entity, revision, acceptedAt}) => {
      const [home, audit] = await Promise.all([
        transaction.get(homeRef),
        transaction.get(auditRef),
      ]);
      if (!home.exists || home.get("world") !== input.authorityWorld) {
        throw new Error("Admin safety command used the wrong home authority.");
      }
      if (audit.exists) {
        throw new Error("Admin safety audit exists without its operation.");
      }
      const current = parseAccountSafetyProjection(
        entity,
        input.authorityWorld,
      );
      const next = applyAdminAction(current, input.action, acceptedAt);
      transaction.set(safetyRef, {
        ...next,
        revision,
        updatedAt: acceptedAt,
      });
      transaction.create(auditRef, {
        operationId,
        targetUid: input.targetUid,
        adminUid: input.adminUid,
        action: input.action,
        reason,
        reference,
        revision,
        createdAt: acceptedAt,
        expireAt: Timestamp.fromMillis(
          acceptedAt.toMillis() + ACCOUNT_SAFETY_AUDIT_RETENTION_MILLIS,
        ),
      });
    },
  });
}

/** Requires the local mirror before a content or participation write. */
export async function assertAccountSafetyAllows(
  transaction: Transaction,
  firestore: Firestore,
  uid: string,
  family: AccountSafetyOperationFamily,
  now: Timestamp,
): Promise<void> {
  const snapshot = await transaction.get(accountSafetyRef(firestore, uid));
  let safety: AccountSafetyProjection;
  try {
    safety = parseAccountSafetyProjection(snapshot);
  } catch {
    throw new HttpsError(
      "failed-precondition",
      "This world is still preparing your account safety state.",
      {reason: "world-not-ready"},
    );
  }
  assertAccountSafetyProjectionAllows(safety, family, now);
}

/** Rejects a disallowed request before paid or storage-heavy preprocessing. */
export async function assertAccountSafetyPreflight(
  firestore: Firestore,
  uid: string,
  family: AccountSafetyOperationFamily,
  now: Timestamp,
): Promise<void> {
  const snapshot = await accountSafetyRef(firestore, uid).get();
  let safety: AccountSafetyProjection;
  try {
    safety = parseAccountSafetyProjection(snapshot);
  } catch {
    throw new HttpsError(
      "failed-precondition",
      "This world is still preparing your account safety state.",
      {reason: "world-not-ready"},
    );
  }
  assertAccountSafetyProjectionAllows(safety, family, now);
}

/** Converts a parsed local projection into the stable callable errors. */
function assertAccountSafetyProjectionAllows(
  safety: AccountSafetyProjection,
  family: AccountSafetyOperationFamily,
  now: Timestamp,
): void {
  const denialReason = accountSafetyDenialReason(safety, family, now);
  if (denialReason === "account-banned") {
    throw new HttpsError(
      "permission-denied",
      "Your account is currently banned.",
      {reason: "account-banned"},
    );
  }
  if (denialReason === "posting-restricted") {
    throw new HttpsError(
      "permission-denied",
      "Your account is temporarily restricted from posting.",
      {reason: "posting-restricted"},
    );
  }
}

/** Derives the local enforcement result without performing a database read. */
export function accountSafetyDenialReason(
  safety: AccountSafetyProjection,
  family: AccountSafetyOperationFamily,
  now: Timestamp,
): AccountSafetyDenialReason {
  if (safety.isPermanentlyBanned || isFuture(safety.bannedUntil, now)) {
    return "account-banned";
  }
  if (family === "contentWrite" &&
      isFuture(safety.restrictedUntil, now)) {
    return "posting-restricted";
  }
  return null;
}

async function replicateAccountSafety(
  context: GlobalReplicationApplyContext,
): Promise<number> {
  if (context.operation.ownerUid !== context.operation.entityId) {
    throw new Error("Account safety operation owner is invalid.");
  }
  const source = parseAccountSafetyProjection(
    await accountSafetyRef(
      context.authorityFirestore,
      context.operation.ownerUid,
    ).get(),
    context.operation.authorityWorld,
  );
  if (source.revision < context.operation.revision) {
    throw new Error("Account safety authority is behind its operation.");
  }
  const destinationRef = accountSafetyRef(
    context.destinationFirestore,
    context.operation.ownerUid,
  );
  return context.destinationFirestore.runTransaction(async (transaction) => {
    const destination = await transaction.get(destinationRef);
    if (destination.exists) {
      const current = parseAccountSafetyProjection(destination);
      if (current.revision >= source.revision) return current.revision;
    }
    transaction.set(destinationRef, {...source});
    return source.revision;
  });
}

async function finalizeAccountSafetyOperation(
  context: GlobalReplicationFinalizeContext,
): Promise<void> {
  if (context.destinationWorld !== context.operation.authorityWorld) return;
  const receipts = await accountSafetyRef(
    context.authorityFirestore,
    context.operation.ownerUid,
  ).collection("appliedEvents")
    .where("operationId", "==", context.operation.operationId)
    .limit(1)
    .get();
  if (receipts.empty) return;
  const completedAt = context.operation.completedAt;
  if (completedAt === undefined) {
    throw new Error("Completed account safety operation has no timestamp.");
  }
  const expireAt = Timestamp.fromMillis(
    completedAt.toMillis() +
      ACCOUNT_SAFETY_AUDIT_RETENTION_MILLIS,
  );
  await receipts.docs[0].ref.update({expireAt});
}

/** Applies one admin action without coupling score and explicit overrides. */
export function applyAdminAction(
  current: AccountSafetyProjection,
  action: AdminAccountSafetyAction,
  now: Timestamp,
): AccountSafetyProjection {
  parseAdminAccountSafetyAction(action);
  const decayed = applyAccountSafetyDecay(
    current.violationPoints,
    current.nextPointDecayAt,
    now,
  );
  let violationPoints = decayed.violationPoints;
  let nextPointDecayAt = decayed.nextPointDecayAt;
  let adminRestrictedUntil = current.adminRestrictedUntil;
  let adminBannedUntil = current.adminBannedUntil;
  let isPermanentlyBanned = current.isPermanentlyBanned;

  switch (action.type) {
  case "adjustPoints":
    violationPoints = Math.max(
      0,
      Math.min(ACCOUNT_SAFETY_MAX_POINTS, violationPoints + action.delta),
    );
    nextPointDecayAt = violationPoints === 0 ? null : nextPointDecayAt ??
      Timestamp.fromMillis(
        now.toMillis() + ACCOUNT_SAFETY_DECAY_GRACE_MILLIS +
          ACCOUNT_SAFETY_DECAY_INTERVAL_MILLIS,
      );
    break;
  case "setRestriction":
    adminRestrictedUntil = Timestamp.fromMillis(
      now.toMillis() + action.durationDays * 24 * 60 * 60 * 1000,
    );
    break;
  case "clearRestriction":
    adminRestrictedUntil = null;
    break;
  case "setBan":
    adminBannedUntil = Timestamp.fromMillis(
      now.toMillis() + action.durationDays * 24 * 60 * 60 * 1000,
    );
    isPermanentlyBanned = false;
    break;
  case "setPermanentBan":
    adminBannedUntil = null;
    isPermanentlyBanned = true;
    break;
  case "clearBan":
    adminBannedUntil = null;
    isPermanentlyBanned = false;
    break;
  }
  return Object.freeze({
    ...current,
    violationPoints,
    nextPointDecayAt,
    adminRestrictedUntil,
    adminBannedUntil,
    restrictedUntil: latestTimestamp(
      current.automatedRestrictedUntil,
      adminRestrictedUntil,
    ),
    bannedUntil: latestTimestamp(
      current.automatedBannedUntil,
      adminBannedUntil,
    ),
    isPermanentlyBanned,
    updatedAt: now,
  });
}

function isFuture(value: Timestamp | null, now: Timestamp): boolean {
  return value !== null && value.toMillis() > now.toMillis();
}

function latestTimestamp(
  first: Timestamp | null,
  second: Timestamp | null,
): Timestamp | null {
  if (first === null) return second;
  if (second === null) return first;
  return first.toMillis() >= second.toMillis() ? first : second;
}

function laterOf(first: Timestamp | null, second: Timestamp): Timestamp {
  return first !== null && first.toMillis() >= second.toMillis() ?
    first : second;
}

function sameTimestamp(
  first: Timestamp | null,
  second: Timestamp | null,
): boolean {
  return first === null ? second === null :
    second !== null && first.isEqual(second);
}

function requireUid(value: unknown): string {
  if (typeof value !== "string" || value.length === 0 ||
      value.length > MAX_UID_LENGTH || value.includes("/")) {
    throw new Error("Account safety UID is invalid.");
  }
  return value;
}

function requireEventId(value: unknown): string {
  if (typeof value !== "string" || value.length === 0 ||
      value.length > MAX_EVENT_ID_LENGTH || value.includes("/")) {
    throw new Error("Account safety event ID is invalid.");
  }
  return value;
}

function requireValue(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0 ||
      value.length > 256 || value.includes("/") || /\s/.test(value)) {
    throw new Error(`Account safety ${field} is invalid.`);
  }
  return value;
}

function requireTrimmedText(
  value: unknown,
  field: string,
  maxLength: number,
): string {
  if (typeof value !== "string" || value.trim() !== value ||
      value.length === 0 || value.length > maxLength) {
    throw new Error(`Account safety ${field} is invalid.`);
  }
  return value;
}

export function parseAdminAccountSafetyAction(
  value: unknown,
): AdminAccountSafetyAction {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("Admin account safety action is invalid.");
  }
  const action = value as Record<string, unknown>;
  switch (action.type) {
  case "adjustPoints":
    if (Object.keys(action).length !== 2 ||
        typeof action.delta !== "number" ||
        !Number.isSafeInteger(action.delta) ||
        action.delta < -100 || action.delta > 100 || action.delta === 0) {
      break;
    }
    return value as AdminAccountSafetyAction;
  case "setRestriction":
    if (Object.keys(action).length === 2 &&
        (action.durationDays === 1 || action.durationDays === 3 ||
         action.durationDays === 7)) {
      return value as AdminAccountSafetyAction;
    }
    break;
  case "setBan":
    if (Object.keys(action).length === 2 &&
        (action.durationDays === 7 || action.durationDays === 30)) {
      return value as AdminAccountSafetyAction;
    }
    break;
  case "clearRestriction":
  case "setPermanentBan":
  case "clearBan":
    if (Object.keys(action).length === 1) {
      return value as AdminAccountSafetyAction;
    }
    break;
  default:
    break;
  }
  throw new Error("Admin account safety action is invalid.");
}

function requirePositiveInteger(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`Account safety ${field} is invalid.`);
  }
  return value;
}

function requirePoints(value: unknown): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) ||
      value < 0 || value > ACCOUNT_SAFETY_MAX_POINTS) {
    throw new Error("Account safety points are invalid.");
  }
  return value;
}

function requireBoolean(value: unknown, field: string): boolean {
  if (typeof value !== "boolean") {
    throw new Error(`Account safety ${field} is invalid.`);
  }
  return value;
}

function requireTimestamp(value: unknown, field: string): Timestamp {
  if (!(value instanceof Timestamp)) {
    throw new Error(`Account safety ${field} is invalid.`);
  }
  return value;
}

function requireNullableTimestamp(
  value: unknown,
  field: string,
): Timestamp | null {
  return value === null ? null : requireTimestamp(value, field);
}
