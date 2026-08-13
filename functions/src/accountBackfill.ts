/* eslint-disable require-jsdoc, valid-jsdoc */

import {Timestamp} from "firebase-admin/firestore";

import {
  initialAccountSafetyData,
  parseAccountSafetyData,
} from "./accountSafety";
import {derivedGlobalOperationId} from "./globalOperations";

export const ACCOUNT_HOME_EPOCH = 1;

export const ACCOUNT_BACKFILL_OPERATION_FIELDS = Object.freeze({
  profile: "profileReplicationOperationId",
  entitlement: "entitlementReplicationOperationId",
  safety: "safetyReplicationOperationId",
} as const);

const BACKFILL_OPERATION_ROOT = "00000000-0000-7000-8000-000000000000";
const UUID_V7_PATTERN = new RegExp(
  "^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-" +
    "[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
);
const MAX_DISPLAY_NAME_LENGTH = 20;
const MAX_EMAIL_LENGTH = 320;
const MAX_PHOTO_URL_LENGTH = 2_000;
const LANGUAGE_PREFERENCES = new Set([
  "system",
  "en",
  "ja",
  "ko",
  "zh-Hans",
  "zh-Hant",
]);

export interface AccountBackfillIdentity {
  readonly uid: string;
  readonly displayName: string | null;
  readonly email: string | null;
  readonly photoUrl: string | null;
  readonly createdAt: Timestamp;
}

export interface AccountAuthorityInput {
  readonly identity: AccountBackfillIdentity;
  readonly now: Timestamp;
  readonly activeNoteCount: number;
  readonly home: Readonly<Record<string, unknown>> | null;
  readonly user: Readonly<Record<string, unknown>> | null;
  readonly profile: Readonly<Record<string, unknown>> | null;
  readonly entitlement: Readonly<Record<string, unknown>> | null;
  readonly usage: Readonly<Record<string, unknown>> | null;
  readonly safety: Readonly<Record<string, unknown>> | null;
}

export interface AccountAuthorityData {
  readonly home: Readonly<Record<string, unknown>>;
  readonly user: Readonly<Record<string, unknown>>;
  readonly profile: Readonly<Record<string, unknown>>;
  readonly entitlement: Readonly<Record<string, unknown>>;
  readonly usage: Readonly<Record<string, unknown>>;
  readonly safety: Readonly<Record<string, unknown>>;
}

const PUBLIC_PROFILE_REPLICATED_FIELDS = [
  "displayName",
  "photoUrl",
  "photoVersion",
  "revision",
  "createdAt",
  "updatedAt",
] as const;

/** Builds the deterministic operation ID used to repair one account bundle. */
export function accountBackfillOperationId(
  uid: string,
  kind: "profile" | "entitlement" | "safety",
): string {
  requireUid(uid);
  return derivedGlobalOperationId(
    BACKFILL_OPERATION_ROOT,
    `account-backfill:${kind}:${uid}`,
  );
}

/** Normalizes one Asia authority bundle without removing legacy fields. */
export function accountAuthorityData(
  input: AccountAuthorityInput,
): AccountAuthorityData {
  const uid = requireUid(input.identity.uid);
  requireTimestamp(input.identity.createdAt, "identity.createdAt");
  requireTimestamp(input.now, "now");
  requireNonNegativeInteger(input.activeNoteCount, "activeNoteCount");

  const displayName = displayNameOf(
    input.user?.displayName ??
      input.profile?.displayName ??
      input.identity.displayName,
  );
  const email = nullableBoundedString(
    input.user?.email ?? input.identity.email,
    "email",
    MAX_EMAIL_LENGTH,
  );
  const photoUrl = nullableBoundedString(
    input.user?.photoUrl ??
      input.profile?.photoUrl ??
      input.identity.photoUrl,
    "photoUrl",
    MAX_PHOTO_URL_LENGTH,
  );
  const createdAt = timestampOr(
    input.user?.createdAt ?? input.profile?.createdAt,
    input.identity.createdAt,
  );

  const homeWorld = input.home?.world ?? "asia";
  const homeEpoch = input.home?.epoch ?? ACCOUNT_HOME_EPOCH;
  if (homeWorld !== "asia" || homeEpoch !== ACCOUNT_HOME_EPOCH) {
    throw new Error("Account home assignment is incompatible.");
  }
  const home = Object.freeze({
    world: "asia",
    epoch: ACCOUNT_HOME_EPOCH,
    [ACCOUNT_BACKFILL_OPERATION_FIELDS.profile]: operationIdOr(
      input.home?.[ACCOUNT_BACKFILL_OPERATION_FIELDS.profile],
      accountBackfillOperationId(uid, "profile"),
    ),
    [ACCOUNT_BACKFILL_OPERATION_FIELDS.entitlement]: operationIdOr(
      input.home?.[ACCOUNT_BACKFILL_OPERATION_FIELDS.entitlement],
      accountBackfillOperationId(uid, "entitlement"),
    ),
    [ACCOUNT_BACKFILL_OPERATION_FIELDS.safety]: operationIdOr(
      input.home?.[ACCOUNT_BACKFILL_OPERATION_FIELDS.safety],
      accountBackfillOperationId(uid, "safety"),
    ),
    createdAt: timestampOr(input.home?.createdAt, createdAt),
  });

  const languagePreference = input.user?.languagePreference ?? "system";
  if (typeof languagePreference !== "string" ||
      !LANGUAGE_PREFERENCES.has(languagePreference)) {
    throw new Error("Account language preference is invalid.");
  }
  const languagePreferenceRevision = input.user?.languagePreferenceRevision ??
    0;
  requireNonNegativeInteger(
    languagePreferenceRevision,
    "languagePreferenceRevision",
  );
  const user = Object.freeze({
    displayName,
    email,
    photoUrl,
    languagePreference,
    languagePreferenceRevision,
    createdAt,
    updatedAt: timestampOr(input.user?.updatedAt, input.now),
  });

  const profile = Object.freeze({
    displayName,
    photoUrl,
    photoVersion: positiveIntegerOr(input.profile?.photoVersion, 1),
    revision: positiveIntegerOr(input.profile?.revision, 1),
    followerCount: nonNegativeIntegerOr(input.profile?.followerCount, 0),
    followingCount: nonNegativeIntegerOr(input.profile?.followingCount, 0),
    createdAt: timestampOr(input.profile?.createdAt, createdAt),
    updatedAt: timestampOr(input.profile?.updatedAt, input.now),
  });

  const legacyPremium = input.user?.isPremium;
  const isPremium = input.entitlement?.isPremium ??
    (typeof legacyPremium === "boolean" ? legacyPremium : false);
  if (typeof isPremium !== "boolean") {
    throw new Error("Account entitlement isPremium is invalid.");
  }
  const sourceCheckedAt = input.entitlement?.sourceCheckedAt ?? null;
  if (sourceCheckedAt !== null) {
    requireTimestamp(sourceCheckedAt, "sourceCheckedAt");
  }
  const entitlement = Object.freeze({
    isPremium,
    revision: positiveIntegerOr(input.entitlement?.revision, 1),
    sourceCheckedAt,
    updatedAt: timestampOr(input.entitlement?.updatedAt, input.now),
  });

  const usage = Object.freeze({
    activeNoteCount: input.activeNoteCount,
    updatedAt: timestampOr(input.usage?.updatedAt, input.now),
  });

  const safety: Readonly<Record<string, unknown>> = Object.freeze({
    ...(input.safety === null ?
      initialAccountSafetyData("asia", input.now) :
      normalizeSafety(input.safety)),
  });

  return Object.freeze({home, user, profile, entitlement, usage, safety});
}

/** Returns whether a destination projection needs the source revision. */
export function shouldWriteProjection(
  source: Readonly<Record<string, unknown>>,
  destination: Readonly<Record<string, unknown>> | null,
): boolean {
  const sourceRevision = requirePositiveInteger(
    source.revision,
    "source.revision",
  );
  if (destination === null) return true;
  const destinationRevision = requirePositiveInteger(
    destination.revision,
    "destination.revision",
  );
  if (destinationRevision > sourceRevision) {
    throw new Error("Destination projection is ahead of its authority.");
  }
  if (destinationRevision < sourceRevision) return true;
  if (!hasMatchingFields(source, destination, Object.keys(source))) {
    throw new Error("Equal-revision account projections diverge.");
  }
  return false;
}

/** Returns whether any canonical source field is missing or different. */
export function shouldWriteCanonicalFields(
  source: Readonly<Record<string, unknown>>,
  destination: Readonly<Record<string, unknown>> | null,
): boolean {
  return destination === null ||
    !hasMatchingFields(source, destination, Object.keys(source));
}

/** Returns whether replicated public-profile fields need an update. */
export function shouldWritePublicProfile(
  source: Readonly<Record<string, unknown>>,
  destination: Readonly<Record<string, unknown>> | null,
): boolean {
  const sourceRevision = requirePositiveInteger(
    source.revision,
    "source.revision",
  );
  if (destination === null) return true;
  const destinationRevision = requirePositiveInteger(
    destination.revision,
    "destination.revision",
  );
  if (destinationRevision > sourceRevision) {
    throw new Error("Destination public profile is ahead of its authority.");
  }
  if (destinationRevision < sourceRevision) return true;
  if (!hasMatchingFields(
    source,
    destination,
    PUBLIC_PROFILE_REPLICATED_FIELDS,
  )) {
    throw new Error("Equal-revision public profiles diverge.");
  }
  return false;
}

/** Builds a mirror update without replacing destination social counters. */
export function publicProfileMirrorData(
  source: Readonly<Record<string, unknown>>,
): Readonly<Record<string, unknown>> {
  return Object.freeze(Object.fromEntries(
    PUBLIC_PROFILE_REPLICATED_FIELDS.map((field) => [field, source[field]]),
  ));
}

/** Returns whether a destination home marker needs to be copied. */
export function shouldWriteHomeMarker(
  source: Readonly<Record<string, unknown>>,
  destination: Readonly<Record<string, unknown>> | null,
): boolean {
  if (source.world !== "asia" || source.epoch !== ACCOUNT_HOME_EPOCH) {
    throw new Error("Source home marker is invalid.");
  }
  if (destination === null) return true;
  if (destination.world !== source.world ||
      destination.epoch !== source.epoch) {
    throw new Error("Destination home marker is incompatible.");
  }
  return !hasMatchingFields(source, destination, Object.keys(source));
}

function normalizeSafety(
  value: Readonly<Record<string, unknown>>,
): Readonly<Record<string, unknown>> {
  return Object.freeze({...parseAccountSafetyData(value, "asia")});
}

function displayNameOf(value: unknown): string {
  if (typeof value !== "string") return "User";
  const normalized = value.trim();
  if (normalized.length === 0) return "User";
  return Array.from(normalized).slice(0, MAX_DISPLAY_NAME_LENGTH).join("");
}

function nullableBoundedString(
  value: unknown,
  field: string,
  maximum: number,
): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") {
    throw new Error(`Account ${field} is invalid.`);
  }
  const normalized = value.trim();
  if (normalized.length === 0) return null;
  return normalized.slice(0, maximum);
}

function timestampOr(value: unknown, fallback: Timestamp): Timestamp {
  if (value === undefined || value === null) return fallback;
  return requireTimestamp(value, "timestamp");
}

function operationIdOr(value: unknown, fallback: string): string {
  if (value === undefined || value === null) return fallback;
  if (typeof value !== "string" || !UUID_V7_PATTERN.test(value)) {
    throw new Error("Account bootstrap operation ID is invalid.");
  }
  return value;
}

function positiveIntegerOr(value: unknown, fallback: number): number {
  if (value === undefined || value === null) return fallback;
  return requirePositiveInteger(value, "positive integer");
}

function nonNegativeIntegerOr(value: unknown, fallback: number): number {
  if (value === undefined || value === null) return fallback;
  return requireNonNegativeInteger(value, "non-negative integer");
}

function requirePositiveInteger(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`Account ${field} is invalid.`);
  }
  return value;
}

function requireNonNegativeInteger(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw new Error(`Account ${field} is invalid.`);
  }
  return value;
}

function requireTimestamp(value: unknown, field: string): Timestamp {
  if (!(value instanceof Timestamp)) {
    throw new Error(`Account ${field} is invalid.`);
  }
  return value;
}

function requireUid(value: string): string {
  if (value.length === 0 || value.length > 128 || value.includes("/") ||
      /\s/.test(value)) {
    throw new Error("Account UID is invalid.");
  }
  return value;
}

function sameValue(left: unknown, right: unknown): boolean {
  if (left instanceof Timestamp && right instanceof Timestamp) {
    return left.isEqual(right);
  }
  if (Array.isArray(left) && Array.isArray(right)) {
    return left.length === right.length &&
      left.every((value, index) => sameValue(value, right[index]));
  }
  if (isRecord(left) && isRecord(right)) {
    const leftKeys = Object.keys(left).sort();
    const rightKeys = Object.keys(right).sort();
    return sameValue(leftKeys, rightKeys) &&
      leftKeys.every((key) => sameValue(left[key], right[key]));
  }
  return left === right;
}

function hasMatchingFields(
  source: Readonly<Record<string, unknown>>,
  destination: Readonly<Record<string, unknown>>,
  fields: readonly string[],
): boolean {
  return fields.every((field) =>
    field in destination && sameValue(source[field], destination[field]),
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null &&
    !Array.isArray(value) && !(value instanceof Timestamp);
}
