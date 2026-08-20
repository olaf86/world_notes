/* eslint-disable require-jsdoc, valid-jsdoc */

import {
  createHash,
  createHmac,
  randomBytes,
  timingSafeEqual,
} from "node:crypto";

import {Timestamp} from "firebase-admin/firestore";
import {defineSecret} from "firebase-functions/params";

import {GLOBAL_OPERATION_TERMINAL_RETENTION_MILLIS} from "./globalOperations";

export const NOTE_ADMINISTRATOR_INVITE_LIFETIME_MILLIS =
  7 * 24 * 60 * 60 * 1000;
export const NOTE_ADMINISTRATOR_AUDIT_RETENTION_MILLIS =
  365 * 24 * 60 * 60 * 1000;
export const NOTE_ADMINISTRATOR_MAX_PENDING_INVITES = 10;
export const NOTE_ADMINISTRATOR_MAX_ACTIVE = 10;

export const NOTE_ADMINISTRATOR_INVITE_STATUS = Object.freeze({
  pending: "pending",
  accepted: "accepted",
  revoked: "revoked",
  expired: "expired",
} as const);

/** Callable-only results that are not persisted invitation states. */
export const NOTE_ADMINISTRATOR_INVITE_OPERATION_RESULT = Object.freeze({
  missing: "missing",
} as const);

export type NoteAdministratorInviteStatus =
  typeof NOTE_ADMINISTRATOR_INVITE_STATUS[
    keyof typeof NOTE_ADMINISTRATOR_INVITE_STATUS
  ];

export interface NoteAdministratorInvitationData {
  readonly inviteId: string;
  readonly placeId: string;
  readonly targetUid: string;
  readonly invitedByUid: string;
  readonly nonce: string;
  readonly revision: number;
  readonly status: NoteAdministratorInviteStatus;
  readonly createdAt: Timestamp;
  readonly updatedAt: Timestamp;
  /** Deadline after which a pending invitation cannot be accepted. */
  readonly expiresAt: Timestamp;
  /** Time the invitation entered its accepted, revoked, or expired state. */
  readonly terminalAt: Timestamp | null;
  /** Firestore TTL purge deadline for terminal invitation history. */
  readonly purgeAt: Timestamp | null;
}

export interface NoteAdministratorInvitationToken {
  readonly version: 1;
  readonly worldId: string;
  readonly inviteId: string;
  readonly revision: number;
  readonly nonce: string;
}

const TOKEN_PREFIX = "nai1";
const ID_PATTERN = /^[0-9a-f]{64}$/;
const WORLD_PATTERN = /^[a-z][A-Za-z0-9]{1,31}$/;
const VALUE_PATTERN = /^[^/\s]{1,256}$/;
const NONCE_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const SIGNATURE_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const INVITATION_FIELDS = new Set([
  "inviteId",
  "placeId",
  "targetUid",
  "invitedByUid",
  "nonce",
  "revision",
  "status",
  "createdAt",
  "updatedAt",
  "expiresAt",
  "terminalAt",
  "purgeAt",
]);

// Operator setup required before deployment:
// firebase functions:secrets:set NOTE_ADMINISTRATOR_INVITE_SIGNING_KEY
export const NOTE_ADMINISTRATOR_INVITE_SIGNING_KEY = defineSecret(
  "NOTE_ADMINISTRATOR_INVITE_SIGNING_KEY",
);

/** Returns the sole invitation document ID for one note and target user. */
export function noteAdministratorInvitationId(
  placeId: string,
  targetUid: string,
): string {
  requireValue(placeId, "placeId");
  requireValue(targetUid, "targetUid");
  return createHash("sha256")
    .update(JSON.stringify([placeId, targetUid]), "utf8")
    .digest("hex");
}

/** Generates one 256-bit URL-safe invitation nonce. */
export function newNoteAdministratorInvitationNonce(): string {
  return randomBytes(32).toString("base64url");
}

/** Creates an authenticated route token without exposing Firebase resources. */
export function signNoteAdministratorInvitationToken(
  token: NoteAdministratorInvitationToken,
  signingKey: string,
): string {
  validateTokenFields(token);
  requireSigningKey(signingKey);
  const payload = tokenPayload(token);
  const signature = createHmac("sha256", signingKey)
    .update(payload, "utf8")
    .digest("base64url");
  return `${payload}.${signature}`;
}

/** Verifies and parses one versioned administrator invitation token. */
export function verifyNoteAdministratorInvitationToken(
  value: unknown,
  signingKey: string,
): NoteAdministratorInvitationToken {
  requireSigningKey(signingKey);
  if (typeof value !== "string" || value.length > 512) {
    throw new Error("Note administrator invitation token is invalid.");
  }
  const parts = value.split(".");
  if (parts.length !== 6 || parts[0] !== TOKEN_PREFIX ||
      !SIGNATURE_PATTERN.test(parts[5])) {
    throw new Error("Note administrator invitation token is invalid.");
  }
  const revision = Number(parts[3]);
  const token = Object.freeze({
    version: 1 as const,
    worldId: parts[1],
    inviteId: parts[2],
    revision,
    nonce: parts[4],
  });
  validateTokenFields(token);
  const payload = parts.slice(0, 5).join(".");
  const expected = createHmac("sha256", signingKey)
    .update(payload, "utf8")
    .digest();
  const received = Buffer.from(parts[5], "base64url");
  if (received.length !== expected.length ||
      !timingSafeEqual(received, expected)) {
    throw new Error("Note administrator invitation token is invalid.");
  }
  return token;
}

/** Builds a new pending invitation with one seven-day validity window. */
export function newNoteAdministratorInvitationData(
  input: Readonly<{
    placeId: string;
    targetUid: string;
    invitedByUid: string;
    nonce: string;
    revision: number;
  }>,
  now: Timestamp,
): NoteAdministratorInvitationData {
  const inviteId = noteAdministratorInvitationId(
    input.placeId,
    input.targetUid,
  );
  requireValue(input.invitedByUid, "invitedByUid");
  requireNonce(input.nonce);
  requirePositiveInteger(input.revision, "revision");
  return Object.freeze({
    inviteId,
    ...input,
    status: NOTE_ADMINISTRATOR_INVITE_STATUS.pending,
    createdAt: now,
    updatedAt: now,
    expiresAt: Timestamp.fromMillis(
      now.toMillis() + NOTE_ADMINISTRATOR_INVITE_LIFETIME_MILLIS,
    ),
    terminalAt: null,
    purgeAt: null,
  });
}

/** Parses persisted invitation data and enforces lifecycle invariants. */
export function parseNoteAdministratorInvitation(
  value: unknown,
  expectedInviteId?: string,
): NoteAdministratorInvitationData {
  const data = requireRecord(value);
  if (Object.keys(data).length !== INVITATION_FIELDS.size ||
      [...INVITATION_FIELDS].some((field) => !(field in data))) {
    throw new Error("Note administrator invitation fields are invalid.");
  }
  const inviteId = requirePattern(data.inviteId, "inviteId", ID_PATTERN);
  if (expectedInviteId !== undefined && inviteId !== expectedInviteId) {
    throw new Error("Note administrator invitation route is invalid.");
  }
  const placeId = requirePattern(data.placeId, "placeId", VALUE_PATTERN);
  const targetUid = requirePattern(data.targetUid, "targetUid", VALUE_PATTERN);
  if (noteAdministratorInvitationId(placeId, targetUid) !== inviteId) {
    throw new Error("Note administrator invitation identity is invalid.");
  }
  const status = requireStatus(data.status);
  const createdAt = requireTimestamp(data.createdAt, "createdAt");
  const updatedAt = requireTimestamp(data.updatedAt, "updatedAt");
  const expiresAt = requireTimestamp(data.expiresAt, "expiresAt");
  const terminalAt = requireNullableTimestamp(data.terminalAt, "terminalAt");
  const purgeAt = requireNullableTimestamp(data.purgeAt, "purgeAt");
  if (updatedAt.toMillis() < createdAt.toMillis() ||
      expiresAt.toMillis() <= createdAt.toMillis()) {
    throw new Error("Note administrator invitation timestamps are invalid.");
  }
  if (status === NOTE_ADMINISTRATOR_INVITE_STATUS.pending) {
    if (terminalAt !== null || purgeAt !== null) {
      throw new Error("Pending administrator invitation is terminal.");
    }
  } else {
    if (terminalAt === null || purgeAt === null ||
        terminalAt.toMillis() < createdAt.toMillis() ||
        updatedAt.toMillis() < terminalAt.toMillis() ||
        purgeAt.toMillis() < terminalAt.toMillis()) {
      throw new Error("Terminal administrator invitation is invalid.");
    }
  }
  return Object.freeze({
    inviteId,
    placeId,
    targetUid,
    invitedByUid: requirePattern(
      data.invitedByUid,
      "invitedByUid",
      VALUE_PATTERN,
    ),
    nonce: requirePattern(data.nonce, "nonce", NONCE_PATTERN),
    revision: requirePositiveInteger(data.revision, "revision"),
    status,
    createdAt,
    updatedAt,
    expiresAt,
    terminalAt,
    purgeAt,
  });
}

/** Returns a terminal copy retained for the shared 30-day period. */
export function terminalNoteAdministratorInvitation(
  invitation: NoteAdministratorInvitationData,
  status: Exclude<NoteAdministratorInviteStatus, "pending">,
  now: Timestamp,
): NoteAdministratorInvitationData {
  if (invitation.status !== NOTE_ADMINISTRATOR_INVITE_STATUS.pending) {
    throw new Error("Only a pending administrator invitation can terminate.");
  }
  return parseNoteAdministratorInvitation({
    ...invitation,
    status,
    updatedAt: now,
    terminalAt: now,
    purgeAt: Timestamp.fromMillis(
      now.toMillis() + GLOBAL_OPERATION_TERMINAL_RETENTION_MILLIS,
    ),
  }, invitation.inviteId);
}

/** Returns true once server time reaches the invitation deadline. */
export function isNoteAdministratorInvitationExpired(
  invitation: NoteAdministratorInvitationData,
  now: Timestamp,
): boolean {
  return invitation.expiresAt.toMillis() <= now.toMillis();
}

function tokenPayload(token: NoteAdministratorInvitationToken): string {
  return [
    TOKEN_PREFIX,
    token.worldId,
    token.inviteId,
    String(token.revision),
    token.nonce,
  ].join(".");
}

function validateTokenFields(token: NoteAdministratorInvitationToken): void {
  if (token.version !== 1 || !WORLD_PATTERN.test(token.worldId) ||
      !ID_PATTERN.test(token.inviteId) ||
      !Number.isSafeInteger(token.revision) || token.revision <= 0 ||
      !NONCE_PATTERN.test(token.nonce)) {
    throw new Error("Note administrator invitation token is invalid.");
  }
}

function requireSigningKey(value: string): void {
  if (typeof value !== "string" || Buffer.byteLength(value, "utf8") < 32) {
    throw new Error("Note administrator invitation signing key is invalid.");
  }
}

function requireRecord(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("Note administrator invitation must be an object.");
  }
  return value as Record<string, unknown>;
}

function requireStatus(value: unknown): NoteAdministratorInviteStatus {
  if (value !== NOTE_ADMINISTRATOR_INVITE_STATUS.pending &&
      value !== NOTE_ADMINISTRATOR_INVITE_STATUS.accepted &&
      value !== NOTE_ADMINISTRATOR_INVITE_STATUS.revoked &&
      value !== NOTE_ADMINISTRATOR_INVITE_STATUS.expired) {
    throw new Error("Note administrator invitation status is invalid.");
  }
  return value;
}

function requirePattern(
  value: unknown,
  field: string,
  pattern: RegExp,
): string {
  if (typeof value !== "string" || !pattern.test(value)) {
    throw new Error(`Note administrator invitation ${field} is invalid.`);
  }
  return value;
}

function requireValue(value: unknown, field: string): string {
  return requirePattern(value, field, VALUE_PATTERN);
}

function requireNonce(value: unknown): string {
  return requirePattern(value, "nonce", NONCE_PATTERN);
}

function requirePositiveInteger(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`Note administrator invitation ${field} is invalid.`);
  }
  return value;
}

function requireTimestamp(value: unknown, field: string): Timestamp {
  if (!(value instanceof Timestamp)) {
    throw new Error(`Note administrator invitation ${field} is invalid.`);
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
