import rawWorldCatalog from "./worldCatalog.config.json";

export const WORLD_CATALOG_SCHEMA_VERSION = 1;

export const WORLD_CATALOG_STATES = [
  "provisioning",
  "mirrorOnly",
  "contentEnabled",
  "homeEnabled",
] as const;

export type WorldCatalogState = typeof WORLD_CATALOG_STATES[number];

export interface WorldCatalogEntry {
  readonly worldId: string;
  readonly databaseId: string;
  readonly firestoreLocation: string;
  readonly functionsRegion: string;
  readonly bucketName: string;
  readonly displayNameKey: string;
  readonly catalogState: WorldCatalogState;
  readonly homeAssignmentEnabled: boolean;
  readonly contentAccessEnabled: boolean;
}

export interface WorldCatalog {
  readonly schemaVersion: typeof WORLD_CATALOG_SCHEMA_VERSION;
  readonly catalogVersion: number;
  readonly worlds: readonly WorldCatalogEntry[];
}

const CATALOG_KEYS = new Set([
  "schemaVersion",
  "catalogVersion",
  "worlds",
]);
const WORLD_KEYS = new Set([
  "worldId",
  "databaseId",
  "firestoreLocation",
  "functionsRegion",
  "bucketName",
  "displayNameKey",
  "catalogState",
  "homeAssignmentEnabled",
  "contentAccessEnabled",
]);
const WORLD_ID_PATTERN = /^[a-z][A-Za-z0-9]{1,31}$/;
const DATABASE_ID_PATTERN = /^[a-z][a-z0-9-]{2,61}[a-z0-9]$/;
const REGION_PATTERN = /^[a-z]+(?:-[a-z0-9]+)+[0-9]$/;
const BUCKET_NAME_PATTERN = /^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$/;
const DISPLAY_NAME_KEY_PATTERN = /^world\.[a-z][A-Za-z0-9]*$/;
const CATALOG_STATE_SET: ReadonlySet<string> =
  new Set(WORLD_CATALOG_STATES);

export const WORLD_CATALOG = parseWorldCatalog(rawWorldCatalog);

/**
 * Parses an untrusted catalog value and enforces routing invariants.
 *
 * @param {unknown} value Raw JSON-compatible catalog value.
 * @return {WorldCatalog} Validated immutable catalog.
 */
export function parseWorldCatalog(value: unknown): WorldCatalog {
  const catalog = requireRecord(value, "catalog");
  requireExactKeys(catalog, CATALOG_KEYS, "catalog");

  const schemaVersion = requirePositiveInteger(
    catalog.schemaVersion,
    "catalog.schemaVersion",
  );
  if (schemaVersion !== WORLD_CATALOG_SCHEMA_VERSION) {
    throw new Error(
      "catalog.schemaVersion must be " +
      `${WORLD_CATALOG_SCHEMA_VERSION}; received ${schemaVersion}`,
    );
  }

  const catalogVersion = requirePositiveInteger(
    catalog.catalogVersion,
    "catalog.catalogVersion",
  );
  if (!Array.isArray(catalog.worlds) || catalog.worlds.length === 0) {
    throw new Error("catalog.worlds must be a non-empty array.");
  }

  const worlds = catalog.worlds.map((world, index) =>
    parseWorld(world, `catalog.worlds[${index}]`),
  );
  validateCatalogUniqueness(worlds);

  return Object.freeze({
    schemaVersion: WORLD_CATALOG_SCHEMA_VERSION,
    catalogVersion,
    worlds: Object.freeze(worlds),
  });
}

/**
 * Parses one world entry.
 *
 * @param {unknown} value Raw world entry.
 * @param {string} path Validation path for errors.
 * @return {WorldCatalogEntry} Validated immutable entry.
 */
function parseWorld(value: unknown, path: string): WorldCatalogEntry {
  const world = requireRecord(value, path);
  requireExactKeys(world, WORLD_KEYS, path);

  const worldId = requirePatternedString(
    world.worldId,
    `${path}.worldId`,
    WORLD_ID_PATTERN,
  );
  const databaseId = requireDatabaseId(
    world.databaseId,
    `${path}.databaseId`,
  );
  const firestoreLocation = requirePatternedString(
    world.firestoreLocation,
    `${path}.firestoreLocation`,
    REGION_PATTERN,
  );
  const functionsRegion = requirePatternedString(
    world.functionsRegion,
    `${path}.functionsRegion`,
    REGION_PATTERN,
  );
  const bucketName = requireBucketName(
    world.bucketName,
    `${path}.bucketName`,
  );
  const displayNameKey = requirePatternedString(
    world.displayNameKey,
    `${path}.displayNameKey`,
    DISPLAY_NAME_KEY_PATTERN,
  );
  const catalogState = requireCatalogState(
    world.catalogState,
    `${path}.catalogState`,
  );
  const homeAssignmentEnabled = requireBoolean(
    world.homeAssignmentEnabled,
    `${path}.homeAssignmentEnabled`,
  );
  const contentAccessEnabled = requireBoolean(
    world.contentAccessEnabled,
    `${path}.contentAccessEnabled`,
  );

  validateLifecycleGates({
    path,
    catalogState,
    homeAssignmentEnabled,
    contentAccessEnabled,
  });

  return Object.freeze({
    worldId,
    databaseId,
    firestoreLocation,
    functionsRegion,
    bucketName,
    displayNameKey,
    catalogState,
    homeAssignmentEnabled,
    contentAccessEnabled,
  });
}

/**
 * Validates cross-entry uniqueness and the default database route.
 *
 * @param {WorldCatalogEntry[]} worlds Parsed entries.
 */
function validateCatalogUniqueness(
  worlds: readonly WorldCatalogEntry[],
): void {
  const worldIds = new Set<string>();
  const databaseIds = new Set<string>();
  const bucketNames = new Set<string>();

  for (const world of worlds) {
    requireUnique(worldIds, world.worldId, "worldId");
    requireUnique(databaseIds, world.databaseId, "databaseId");
    requireUnique(bucketNames, world.bucketName, "bucketName");
  }

  if (!databaseIds.has("(default)")) {
    throw new Error("catalog.worlds must contain the (default) database.");
  }
}

interface LifecycleGateInput {
  readonly path: string;
  readonly catalogState: WorldCatalogState;
  readonly homeAssignmentEnabled: boolean;
  readonly contentAccessEnabled: boolean;
}

/**
 * Prevents activation flags from getting ahead of provisioned resources.
 *
 * @param {LifecycleGateInput} input Parsed lifecycle fields.
 */
function validateLifecycleGates(input: LifecycleGateInput): void {
  if (input.contentAccessEnabled &&
      input.catalogState !== "contentEnabled" &&
      input.catalogState !== "homeEnabled") {
    throw new Error(
      `${input.path}.contentAccessEnabled requires an enabled state.`,
    );
  }
  if (input.homeAssignmentEnabled &&
      input.catalogState !== "homeEnabled") {
    throw new Error(
      `${input.path}.homeAssignmentEnabled requires homeEnabled state.`,
    );
  }
  if (input.homeAssignmentEnabled && !input.contentAccessEnabled) {
    throw new Error(
      `${input.path}.homeAssignmentEnabled requires content access.`,
    );
  }
}

/**
 * Requires a JSON object rather than an array or primitive.
 *
 * @param {unknown} value Raw value.
 * @param {string} path Validation path.
 * @return {Record<string, unknown>} Object value.
 */
function requireRecord(
  value: unknown,
  path: string,
): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(`${path} must be an object.`);
  }
  return value as Record<string, unknown>;
}

/**
 * Rejects missing and unknown fields.
 *
 * @param {Record<string, unknown>} value Object to check.
 * @param {Set<string>} expectedKeys Required keys.
 * @param {string} path Validation path.
 */
function requireExactKeys(
  value: Record<string, unknown>,
  expectedKeys: ReadonlySet<string>,
  path: string,
): void {
  const actualKeys = Object.keys(value);
  const missing = [...expectedKeys].filter((key) => !(key in value));
  const unknown = actualKeys.filter((key) => !expectedKeys.has(key));
  if (missing.length > 0 || unknown.length > 0) {
    throw new Error(
      `${path} fields are invalid; missing=[${missing.join(",")}], ` +
      `unknown=[${unknown.join(",")}].`,
    );
  }
}

/**
 * Requires a positive integer.
 *
 * @param {unknown} value Raw value.
 * @param {string} path Validation path.
 * @return {number} Integer value.
 */
function requirePositiveInteger(value: unknown, path: string): number {
  if (typeof value !== "number" ||
      !Number.isSafeInteger(value) ||
      value <= 0) {
    throw new Error(`${path} must be a positive integer.`);
  }
  return value;
}

/**
 * Requires a string matching an identifier pattern.
 *
 * @param {unknown} value Raw value.
 * @param {string} path Validation path.
 * @param {RegExp} pattern Accepted pattern.
 * @return {string} String value.
 */
function requirePatternedString(
  value: unknown,
  path: string,
  pattern: RegExp,
): string {
  if (typeof value !== "string" || !pattern.test(value)) {
    throw new Error(`${path} has an invalid format.`);
  }
  return value;
}

/**
 * Requires a valid default or named Firestore database ID.
 *
 * @param {unknown} value Raw value.
 * @param {string} path Validation path.
 * @return {string} Database ID.
 */
function requireDatabaseId(value: unknown, path: string): string {
  if (value === "(default)") {
    return value;
  }
  return requirePatternedString(value, path, DATABASE_ID_PATTERN);
}

/**
 * Requires a valid Cloud Storage bucket name.
 *
 * @param {unknown} value Raw value.
 * @param {string} path Validation path.
 * @return {string} Bucket name.
 */
function requireBucketName(
  value: unknown,
  path: string,
): string {
  return requirePatternedString(value, path, BUCKET_NAME_PATTERN);
}

/**
 * Requires one supported catalog state.
 *
 * @param {unknown} value Raw value.
 * @param {string} path Validation path.
 * @return {WorldCatalogState} Catalog state.
 */
function requireCatalogState(
  value: unknown,
  path: string,
): WorldCatalogState {
  if (typeof value !== "string" || !CATALOG_STATE_SET.has(value)) {
    throw new Error(`${path} is unsupported.`);
  }
  return value as WorldCatalogState;
}

/**
 * Requires a boolean.
 *
 * @param {unknown} value Raw value.
 * @param {string} path Validation path.
 * @return {boolean} Boolean value.
 */
function requireBoolean(value: unknown, path: string): boolean {
  if (typeof value !== "boolean") {
    throw new Error(`${path} must be a boolean.`);
  }
  return value;
}

/**
 * Adds a value to a uniqueness set.
 *
 * @param {Set<string>} values Existing values.
 * @param {string} value Candidate value.
 * @param {string} fieldName Field name for errors.
 */
function requireUnique(
  values: Set<string>,
  value: string,
  fieldName: string,
): void {
  if (values.has(value)) {
    throw new Error(`Duplicate ${fieldName}: ${value}`);
  }
  values.add(value);
}
