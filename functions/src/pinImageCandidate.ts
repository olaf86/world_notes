/* eslint-disable require-jsdoc, valid-jsdoc */

import {createHash} from "node:crypto";

import {Timestamp} from "firebase-admin/firestore";

export const PIN_IMAGE_CANDIDATE_ACTION = Object.freeze({
  pending: "pending",
} as const);

export interface PinImageCandidateData {
  readonly storagePath: string;
  readonly inputHash: string;
  readonly requestedByUid: string;
  readonly moderationAction: typeof PIN_IMAGE_CANDIDATE_ACTION.pending;
  readonly createdAt: Timestamp;
}

const PATH_SEGMENT = "[^/\\s]{1,256}";
const UUID_V7 =
  "[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-" +
  "[89ab][0-9a-f]{3}-[0-9a-f]{12}";
const PIN_IMAGE_PATH_PATTERN = new RegExp(
  `^images/pins/(${PATH_SEGMENT})/(${PATH_SEGMENT})/(${UUID_V7}[.]webp)$`,
);
const INPUT_HASH_PATTERN = /^[0-9a-f]{64}$/;
const CANDIDATE_FIELDS = new Set([
  "storagePath",
  "inputHash",
  "requestedByUid",
  "moderationAction",
  "createdAt",
]);

/** Binds a pending pin candidate to its immutable Storage object path. */
export function pinImageModerationInputHash(storagePath: string): string {
  requirePinImagePath(storagePath);
  return createHash("sha256")
    .update(JSON.stringify([storagePath]), "utf8")
    .digest("hex");
}

/** Returns the UUID v7 object identity embedded in one valid pin path. */
export function pinImageCandidateId(storagePath: string): string {
  requirePinImagePath(storagePath);
  const fileName = storagePath.split("/").at(-1);
  if (fileName === undefined) {
    throw new Error("Pin image candidate identity is invalid.");
  }
  return fileName.slice(0, -".webp".length);
}

/** Builds one pending candidate after validating its note and owner route. */
export function newPinImageCandidate(
  input: Readonly<{
    storagePath: string;
    placeId: string;
    requestedByUid: string;
  }>,
  createdAt: Timestamp,
): PinImageCandidateData {
  const route = requirePinImagePath(input.storagePath);
  if (route.placeId !== input.placeId ||
      route.ownerUid !== input.requestedByUid) {
    throw new Error("Pin image candidate route is invalid.");
  }
  return Object.freeze({
    storagePath: input.storagePath,
    inputHash: pinImageModerationInputHash(input.storagePath),
    requestedByUid: input.requestedByUid,
    moderationAction: PIN_IMAGE_CANDIDATE_ACTION.pending,
    createdAt,
  });
}

/** Parses one exact persisted pending pin candidate. */
export function parsePinImageCandidate(
  value: unknown,
  expectedPlaceId?: string,
): PinImageCandidateData {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("Pin image candidate must be an object.");
  }
  const data = value as Record<string, unknown>;
  if (Object.keys(data).length !== CANDIDATE_FIELDS.size ||
      [...CANDIDATE_FIELDS].some((field) => !(field in data))) {
    throw new Error("Pin image candidate fields are invalid.");
  }
  const route = requirePinImagePath(data.storagePath);
  if (expectedPlaceId !== undefined && route.placeId !== expectedPlaceId) {
    throw new Error("Pin image candidate note route is invalid.");
  }
  if (data.requestedByUid !== route.ownerUid ||
      data.moderationAction !== PIN_IMAGE_CANDIDATE_ACTION.pending ||
      typeof data.inputHash !== "string" ||
      !INPUT_HASH_PATTERN.test(data.inputHash) ||
      data.inputHash !== pinImageModerationInputHash(route.storagePath) ||
      !(data.createdAt instanceof Timestamp)) {
    throw new Error("Pin image candidate values are invalid.");
  }
  return Object.freeze({
    storagePath: route.storagePath,
    inputHash: data.inputHash,
    requestedByUid: route.ownerUid,
    moderationAction: PIN_IMAGE_CANDIDATE_ACTION.pending,
    createdAt: data.createdAt,
  });
}

/** Returns a valid pending candidate path, or null for absent/invalid data. */
export function pinImageCandidateStoragePath(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  try {
    return parsePinImageCandidate(value).storagePath;
  } catch {
    return null;
  }
}

function requirePinImagePath(value: unknown): Readonly<{
  storagePath: string;
  placeId: string;
  ownerUid: string;
}> {
  if (typeof value !== "string") {
    throw new Error("Pin image storage path is invalid.");
  }
  const match = PIN_IMAGE_PATH_PATTERN.exec(value);
  if (match === null) {
    throw new Error("Pin image storage path is invalid.");
  }
  return Object.freeze({
    storagePath: value,
    placeId: match[1],
    ownerUid: match[2],
  });
}
