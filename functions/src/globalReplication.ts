/* eslint-disable valid-jsdoc */

import {
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";

import {
  GlobalOperationData,
  globalOperationTerminalFields,
  parseGlobalOperation,
} from "./globalOperations";
import {WorldFirestoreProvider} from "./platform/worldFirestoreProvider";
import {WorldCatalog} from "./platform/worldCatalog";

export const GLOBAL_OPERATION_RECONCILE_AFTER_MILLIS = 10 * 60 * 1000;
export const GLOBAL_OPERATION_CRITICAL_AFTER_MILLIS = 24 * 60 * 60 * 1000;
export const GLOBAL_OPERATION_ORDINARY_WARNING_AFTER_MILLIS =
  60 * 60 * 1000;
export const GLOBAL_OPERATION_SAFETY_WARNING_AFTER_MILLIS = 15 * 60 * 1000;
export const GLOBAL_OPERATION_RECONCILE_BATCH_SIZE = 100;

const SAFETY_CRITICAL_OPERATION_TYPES: ReadonlySet<string> = new Set([
  "setUserBlock",
  "applyAccountSafetyEvent",
  "adminUpdateAccountSafety",
]);

export type GlobalOperationAttention = "none" | "warning" | "critical";

export interface GlobalReplicationApplyContext {
  readonly operation: GlobalOperationData;
  readonly authorityFirestore: Firestore;
  readonly destinationFirestore: Firestore;
  readonly destinationWorld: string;
}

/** Installs one operation's current authority state in a destination world. */
export interface GlobalReplicationHandler {
  readonly operationType: string;
  apply(context: GlobalReplicationApplyContext): Promise<number>;
}

/** Immutable operation-type allowlist for replication implementations. */
export class GlobalReplicationHandlerRegistry {
  private readonly handlers = new Map<string, GlobalReplicationHandler>();

  /** Creates a registry and rejects ambiguous operation ownership. */
  constructor(handlers: readonly GlobalReplicationHandler[]) {
    for (const handler of handlers) {
      if (this.handlers.has(handler.operationType)) {
        throw new Error(
          `Duplicate global replication handler: ${handler.operationType}`,
        );
      }
      this.handlers.set(handler.operationType, handler);
    }
  }

  /** Returns the sole handler trusted for an operation type. */
  require(operationType: string): GlobalReplicationHandler {
    const handler = this.handlers.get(operationType);
    if (handler === undefined) {
      throw new Error(
        `No global replication handler is registered for ${operationType}.`,
      );
    }
    return handler;
  }
}

export interface GlobalReplicationRuntime {
  readonly catalog: WorldCatalog;
  readonly firestore: WorldFirestoreProvider;
  readonly handlers: GlobalReplicationHandlerRegistry;
}

export interface GlobalReplicationResult {
  readonly operationId: string;
  readonly status: GlobalOperationData["status"];
  readonly acknowledgedWorlds: readonly string[];
}

/**
 * Applies every missing destination and acknowledges it at the authority.
 *
 * Destination handlers must use a transaction and return the revision that is
 * installed after their call. Returning a newer revision is valid because it
 * also semantically contains the operation's older state transition.
 */
export async function processGlobalOperation(
  authorityWorld: string,
  operationId: string,
  runtime: GlobalReplicationRuntime,
): Promise<GlobalReplicationResult | undefined> {
  if (!runtime.catalog.worlds.some(
    (world) => world.worldId === authorityWorld,
  )) {
    throw new Error(`Unknown authority world: ${authorityWorld}`);
  }
  const authorityFirestore = runtime.firestore.forWorld(authorityWorld);
  const operationRef = authorityFirestore
    .collection("globalOperations")
    .doc(operationId);
  const snapshot = await operationRef.get();
  if (!snapshot.exists) return undefined;

  const operation = parseGlobalOperation(snapshot.data(), operationId);
  if (operation.authorityWorld !== authorityWorld) {
    throw new Error(
      `Operation authority route mismatch: ${operation.operationId}.`,
    );
  }
  if (operation.status !== "pending") {
    return resultFor(operation);
  }

  const handler = runtime.handlers.require(operation.operationType);
  for (const destinationWorld of missingDestinationWorlds(operation)) {
    const destinationFirestore = runtime.firestore.forWorld(destinationWorld);
    const installedRevision = await handler.apply({
      operation,
      authorityFirestore,
      destinationFirestore,
      destinationWorld,
    });
    if (!Number.isSafeInteger(installedRevision) ||
        installedRevision < operation.revision) {
      throw new Error(
        `Handler ${operation.operationType} installed invalid revision ` +
        `${installedRevision} in ${destinationWorld}.`,
      );
    }
    await acknowledgeGlobalOperation({
      authorityFirestore,
      operationId,
      destinationWorld,
      expectedRevision: operation.revision,
    });
  }

  const completed = await operationRef.get();
  if (!completed.exists) return undefined;
  return resultFor(parseGlobalOperation(completed.data(), operationId));
}

interface AcknowledgeGlobalOperationInput {
  readonly authorityFirestore: Firestore;
  readonly operationId: string;
  readonly destinationWorld: string;
  readonly expectedRevision: number;
}

/** Records one destination ack and atomically completes the operation. */
export async function acknowledgeGlobalOperation(
  input: AcknowledgeGlobalOperationInput,
): Promise<void> {
  const operationRef = input.authorityFirestore
    .collection("globalOperations")
    .doc(input.operationId);
  await input.authorityFirestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(operationRef);
    if (!snapshot.exists) {
      throw new Error(`Global operation disappeared: ${input.operationId}.`);
    }
    const operation = parseGlobalOperation(snapshot.data(), input.operationId);
    if (operation.status !== "pending") return;
    if (operation.revision !== input.expectedRevision) {
      throw new Error(
        `Global operation revision changed: ${input.operationId}.`,
      );
    }
    if (!operation.requiredWorlds.includes(input.destinationWorld)) {
      throw new Error(
        `Unexpected destination ${input.destinationWorld} for ` +
        `${input.operationId}.`,
      );
    }
    if (operation.worldAcks[input.destinationWorld] !== undefined) return;

    const acknowledgedAt = Timestamp.now();
    const worldAcks = {
      ...operation.worldAcks,
      [input.destinationWorld]: {
        revision: operation.revision,
        acknowledgedAt,
      },
    };
    const complete = operation.requiredWorlds.every(
      (world) => worldAcks[world] !== undefined,
    );
    transaction.update(operationRef, {
      worldAcks,
      status: complete ? "complete" : "pending",
      updatedAt: acknowledgedAt,
      ...(complete ? globalOperationTerminalFields(acknowledgedAt) : {}),
    });
  });
}

/** Returns destinations that are required but not yet acknowledged. */
export function missingDestinationWorlds(
  operation: GlobalOperationData,
): readonly string[] {
  return operation.requiredWorlds.filter(
    (world) => operation.worldAcks[world] === undefined,
  );
}

/** Derives operator attention without adding mutable operation fields. */
export function deriveGlobalOperationAttention(
  operation: GlobalOperationData,
  now: Timestamp,
): GlobalOperationAttention {
  if (operation.status !== "pending") return "none";
  const age = Math.max(0, now.toMillis() - operation.acceptedAt.toMillis());
  if (age >= GLOBAL_OPERATION_CRITICAL_AFTER_MILLIS) return "critical";
  const warningAfter = SAFETY_CRITICAL_OPERATION_TYPES.has(
    operation.operationType,
  ) ?
    GLOBAL_OPERATION_SAFETY_WARNING_AFTER_MILLIS :
    GLOBAL_OPERATION_ORDINARY_WARNING_AFTER_MILLIS;
  return age >= warningAfter ? "warning" : "none";
}

/** Builds the stable worker result returned by triggers and repair jobs. */
function resultFor(operation: GlobalOperationData): GlobalReplicationResult {
  return Object.freeze({
    operationId: operation.operationId,
    status: operation.status,
    acknowledgedWorlds: Object.freeze(Object.keys(operation.worldAcks)),
  });
}
