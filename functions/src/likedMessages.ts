/* eslint-disable require-jsdoc, valid-jsdoc */

import {Timestamp} from "firebase-admin/firestore";

const LIKED_MESSAGES_FIELDS = new Set([
  "userId",
  "placeId",
  "messageIds",
  "updatedAt",
]);
const DOCUMENT_ID_PATTERN = /^[^/\s]{1,256}$/;
export const MAX_LIKED_MESSAGE_IDS = 10_000;
export const MAX_LIKED_MESSAGE_ID_BYTES = 500_000;

export interface LikedMessagesData {
  readonly userId: string;
  readonly placeId: string;
  readonly messageIds: readonly string[];
  readonly updatedAt: Timestamp;
}

/** Returns one validated, deterministic liked-messages document. */
export function likedMessagesData(
  input: Readonly<{
    userId: string;
    placeId: string;
    messageIds: Iterable<string>;
    updatedAt: Timestamp;
  }>,
): LikedMessagesData {
  const userId = requireDocumentId(input.userId, "userId");
  const placeId = requireDocumentId(input.placeId, "placeId");
  const messageIds = normalizedMessageIds(input.messageIds);
  if (!(input.updatedAt instanceof Timestamp)) {
    throw new Error("Liked messages updatedAt is invalid.");
  }
  return Object.freeze({
    userId,
    placeId,
    messageIds: Object.freeze(messageIds),
    updatedAt: input.updatedAt,
  });
}

/** Parses one trusted persisted liked-messages document. */
export function parseLikedMessages(
  value: unknown,
  expected: Readonly<{userId: string; placeId: string}>,
): LikedMessagesData {
  const data = requireRecord(value);
  if (Object.keys(data).length !== LIKED_MESSAGES_FIELDS.size ||
      [...LIKED_MESSAGES_FIELDS].some((field) => !(field in data))) {
    throw new Error("Liked messages fields are invalid.");
  }
  const parsed = likedMessagesData({
    userId: requireDocumentId(data.userId, "userId"),
    placeId: requireDocumentId(data.placeId, "placeId"),
    messageIds: requireMessageIdArray(data.messageIds),
    updatedAt: requireTimestamp(data.updatedAt),
  });
  if (parsed.userId !== expected.userId ||
      parsed.placeId !== expected.placeId) {
    throw new Error("Liked messages route is invalid.");
  }
  return parsed;
}

/** Returns the bounded final message ID list for one desired Like state. */
export function updatedMessageIds(
  current: readonly string[],
  messageId: string,
  liked: boolean,
): readonly string[] {
  const validatedMessageId = requireDocumentId(messageId, "messageId");
  const next = new Set(normalizedMessageIds(current));
  if (liked) {
    next.add(validatedMessageId);
  } else {
    next.delete(validatedMessageId);
  }
  return Object.freeze(normalizedMessageIds(next));
}

function normalizedMessageIds(value: Iterable<string>): string[] {
  const ids = [...value].map((messageId) =>
    requireDocumentId(messageId, "messageIds"));
  const idBytes = ids.reduce(
    (total, messageId) => total + Buffer.byteLength(messageId, "utf8"),
    0,
  );
  if (ids.length > MAX_LIKED_MESSAGE_IDS ||
      idBytes > MAX_LIKED_MESSAGE_ID_BYTES ||
      new Set(ids).size !== ids.length) {
    throw new Error("Liked messages messageIds is invalid.");
  }
  return ids.sort();
}

function requireMessageIdArray(value: unknown): string[] {
  if (!Array.isArray(value) ||
      value.some((messageId) => typeof messageId !== "string")) {
    throw new Error("Liked messages messageIds is invalid.");
  }
  return value as string[];
}

function requireDocumentId(value: unknown, field: string): string {
  if (typeof value !== "string" || !DOCUMENT_ID_PATTERN.test(value)) {
    throw new Error(`Liked messages ${field} is invalid.`);
  }
  return value;
}

function requireTimestamp(value: unknown): Timestamp {
  if (!(value instanceof Timestamp)) {
    throw new Error("Liked messages updatedAt is invalid.");
  }
  return value;
}

function requireRecord(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("Liked messages must be an object.");
  }
  return value as Record<string, unknown>;
}
