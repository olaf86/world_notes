/* eslint-disable require-jsdoc */

import {randomUUID} from "node:crypto";

import type {CallableRequest} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

const AUDIT_EVENT_TYPE = "worldNotesApplicationAudit";
const MAX_IDENTIFIER_LENGTH = 256;
const AUDIT_IDENTIFIER_FIELDS = [
  "operationId",
  "placeId",
  "messageId",
  "targetUid",
  "targetUserId",
  "userId",
] as const;
const AUDIT_PARAMETER_FIELDS = [
  "blocked",
  "enabled",
  "following",
  "liked",
  "reasonCode",
  "themeId",
  "visibility",
] as const;
const DENIED_ERROR_CODES = new Set([
  "failed-precondition",
  "permission-denied",
  "resource-exhausted",
  "unauthenticated",
]);
const REJECTED_ERROR_CODES = new Set([
  "aborted",
  "already-exists",
  "cancelled",
  "invalid-argument",
  "not-found",
  "out-of-range",
]);

export type ApplicationAuditOutcome =
  "success" | "denied" | "rejected" | "error";

export interface CallableAuditContext {
  readonly action: string;
  readonly actorUid: string | null;
  readonly appId: string | null;
  readonly authProvider: string | null;
  readonly eventId: string;
  readonly identifiers: Readonly<Record<string, string>>;
  readonly parameters: Readonly<Record<string, boolean | number | string>>;
  readonly requestId: string | null;
  readonly startedAtMillis: number;
  readonly traceContext: string | null;
}

export interface ApplicationAuditEvent {
  readonly eventType: typeof AUDIT_EVENT_TYPE;
  readonly schemaVersion: 1;
  readonly eventId: string;
  readonly occurredAt: string;
  readonly durationMillis: number;
  readonly actorUid: string | null;
  readonly action: string;
  readonly outcome: ApplicationAuditOutcome;
  readonly reasonCode: string | null;
  readonly errorCode: string | null;
  readonly worldId: string | null;
  readonly appId: string | null;
  readonly authProvider: string | null;
  readonly requestId: string | null;
  readonly traceContext: string | null;
  readonly identifiers: Readonly<Record<string, string>>;
  readonly parameters: Readonly<Record<string, boolean | number | string>>;
}

export function callableAuditContext<T>(
  request: CallableRequest<T>,
  action: string,
  nowMillis = Date.now(),
): CallableAuditContext {
  const tokenFirebase = objectRecord(request.auth?.token.firebase);
  return Object.freeze({
    action: requireAuditAction(action),
    actorUid: safeIdentifier(request.auth?.uid),
    appId: safeIdentifier(request.app?.appId),
    authProvider: safeIdentifier(tokenFirebase?.sign_in_provider),
    eventId: randomUUID(),
    identifiers: Object.freeze(auditIdentifiers(request.data)),
    parameters: Object.freeze(auditParameters(request.data)),
    requestId: headerValue(request, "function-execution-id"),
    startedAtMillis: nowMillis,
    traceContext: headerValue(request, "x-cloud-trace-context"),
  });
}

export function applicationAuditEvent(
  context: CallableAuditContext,
  outcome: ApplicationAuditOutcome,
  worldId: string | null,
  error?: unknown,
  nowMillis = Date.now(),
): ApplicationAuditEvent {
  const errorCode = errorCodeOf(error);
  return Object.freeze({
    eventType: AUDIT_EVENT_TYPE,
    schemaVersion: 1,
    eventId: context.eventId,
    occurredAt: new Date(nowMillis).toISOString(),
    durationMillis: Math.max(0, nowMillis - context.startedAtMillis),
    actorUid: context.actorUid,
    action: context.action,
    outcome,
    reasonCode: reasonCodeOf(error),
    errorCode,
    worldId: safeIdentifier(worldId),
    appId: context.appId,
    authProvider: context.authProvider,
    requestId: context.requestId,
    traceContext: context.traceContext,
    identifiers: context.identifiers,
    parameters: context.parameters,
  });
}

export function auditOutcomeForError(error: unknown): ApplicationAuditOutcome {
  const code = errorCodeOf(error);
  if (code !== null && DENIED_ERROR_CODES.has(code)) return "denied";
  if (code !== null && REJECTED_ERROR_CODES.has(code)) return "rejected";
  return "error";
}

export function writeApplicationAudit(event: ApplicationAuditEvent): void {
  const message = "World Notes application audit event.";
  switch (event.outcome) {
  case "success":
    logger.info(message, {...event});
    return;
  case "denied":
  case "rejected":
    logger.warn(message, {...event});
    return;
  case "error":
    logger.error(message, {...event});
  }
}

function auditIdentifiers(value: unknown): Record<string, string> {
  const data = objectRecord(value);
  if (data === null) return {};
  const identifiers: Record<string, string> = {};
  for (const field of AUDIT_IDENTIFIER_FIELDS) {
    const identifier = safeIdentifier(data[field]);
    if (identifier !== null) identifiers[field] = identifier;
  }
  return identifiers;
}

function auditParameters(
  value: unknown,
): Record<string, boolean | number | string> {
  const data = objectRecord(value);
  if (data === null) return {};
  const parameters: Record<string, boolean | number | string> = {};
  for (const field of AUDIT_PARAMETER_FIELDS) {
    const parameter = safeParameter(data[field]);
    if (parameter !== null) parameters[field] = parameter;
  }
  const action = objectRecord(data.action);
  if (action !== null) {
    const type = safeIdentifier(action.type);
    if (type !== null) parameters.actionType = type;
    if (typeof action.durationDays === "number" &&
        Number.isSafeInteger(action.durationDays)) {
      parameters.actionDurationDays = action.durationDays;
    }
    if (typeof action.delta === "number" &&
        Number.isSafeInteger(action.delta)) {
      parameters.actionDelta = action.delta;
    }
  } else {
    const actionValue = safeIdentifier(data.action);
    if (actionValue !== null) parameters.action = actionValue;
  }
  return parameters;
}

function reasonCodeOf(error: unknown): string | null {
  const details = objectRecord(objectRecord(error)?.details);
  return safeIdentifier(details?.reason);
}

function errorCodeOf(error: unknown): string | null {
  return safeIdentifier(objectRecord(error)?.code);
}

function safeParameter(value: unknown): boolean | number | string | null {
  if (typeof value === "boolean") return value;
  if (typeof value === "number" && Number.isSafeInteger(value)) return value;
  return safeIdentifier(value);
}

function safeIdentifier(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > MAX_IDENTIFIER_LENGTH) {
    return null;
  }
  for (const character of trimmed) {
    const codePoint = character.codePointAt(0);
    if (codePoint !== undefined && (codePoint <= 31 || codePoint === 127)) {
      return null;
    }
  }
  return trimmed;
}

function objectRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value) ?
    value as Record<string, unknown> : null;
}

function headerValue<T>(
  request: CallableRequest<T>,
  name: string,
): string | null {
  const value = request.rawRequest.headers[name];
  return safeIdentifier(Array.isArray(value) ? value[0] : value);
}

function requireAuditAction(value: string): string {
  const action = safeIdentifier(value);
  if (action === null) throw new Error("Application audit action is invalid.");
  return action;
}
