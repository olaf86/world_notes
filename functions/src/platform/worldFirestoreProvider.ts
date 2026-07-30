import {App, getApp} from "firebase-admin/app";
import {
  Firestore,
  getFirestore,
} from "firebase-admin/firestore";

export const DEFAULT_FIRESTORE_DATABASE_ID = "(default)";

export const WORLD_FIRESTORE_DATABASE_IDS = [
  DEFAULT_FIRESTORE_DATABASE_ID,
  "north-america",
  "europe",
] as const;

export type WorldFirestoreDatabaseId =
  typeof WORLD_FIRESTORE_DATABASE_IDS[number];

const WORLD_FIRESTORE_DATABASE_ID_SET: ReadonlySet<string> =
  new Set(WORLD_FIRESTORE_DATABASE_IDS);

export interface WorldDatabaseConfig {
  readonly worldId: string;
  readonly databaseId: WorldFirestoreDatabaseId;
}

export type WorldFirestoreClientFactory = (
  app: App,
  databaseId: WorldFirestoreDatabaseId,
) => Firestore;

export interface WorldFirestoreProviderOptions {
  readonly appProvider?: () => App;
  readonly clientFactory?: WorldFirestoreClientFactory;
}

/**
 * Creates the Firebase Admin Firestore client for an allowlisted database.
 *
 * This function is the only production boundary allowed to call the Preview
 * named-database overload. Callers should use WorldFirestoreProvider instead.
 *
 * @param {App} app Initialized Firebase Admin app.
 * @param {string} databaseId Allowlisted Firestore database ID.
 * @return {Firestore} Firestore client for the requested database.
 */
export function createAdminWorldFirestoreClient(
  app: App,
  databaseId: WorldFirestoreDatabaseId,
): Firestore {
  assertSupportedDatabaseId(databaseId);
  if (databaseId === DEFAULT_FIRESTORE_DATABASE_ID) {
    return getFirestore(app);
  }
  return getFirestore(app, databaseId);
}

/**
 * Resolves and caches Firestore clients by trusted world ID.
 */
export class WorldFirestoreProvider {
  private readonly worldDatabases =
    new Map<string, WorldDatabaseConfig>();
  private readonly clients = new Map<string, Firestore>();
  private readonly appProvider: () => App;
  private readonly clientFactory: WorldFirestoreClientFactory;

  /**
   * Creates a provider from the trusted world catalog projection.
   *
   * @param {WorldDatabaseConfig[]} worldDatabases Allowlisted
   * world-to-database mappings.
   * @param {WorldFirestoreProviderOptions} options Test and app injection
   * options.
   */
  constructor(
    worldDatabases: readonly WorldDatabaseConfig[],
    options: WorldFirestoreProviderOptions = {},
  ) {
    if (worldDatabases.length === 0) {
      throw new Error("At least one world database config is required.");
    }

    const databaseIds = new Set<string>();
    for (const worldDatabase of worldDatabases) {
      validateWorldDatabase(worldDatabase);
      if (this.worldDatabases.has(worldDatabase.worldId)) {
        throw new Error(`Duplicate world ID: ${worldDatabase.worldId}`);
      }
      if (databaseIds.has(worldDatabase.databaseId)) {
        throw new Error(
          `Duplicate database ID: ${worldDatabase.databaseId}`,
        );
      }
      this.worldDatabases.set(
        worldDatabase.worldId,
        {...worldDatabase},
      );
      databaseIds.add(worldDatabase.databaseId);
    }

    this.appProvider = options.appProvider ?? getApp;
    this.clientFactory =
      options.clientFactory ?? createAdminWorldFirestoreClient;
  }

  /**
   * Returns the cached Firestore client for a trusted world ID.
   *
   * @param {string} worldId Domain world ID from a validated request route.
   * @return {Firestore} Firestore client for the world's database.
   */
  forWorld(worldId: string): Firestore {
    const worldDatabase = this.worldDatabases.get(worldId);
    if (worldDatabase === undefined) {
      throw new Error(`Unknown or inactive world ID: ${worldId}`);
    }

    const cached = this.clients.get(worldDatabase.databaseId);
    if (cached !== undefined) {
      return cached;
    }

    const client = this.clientFactory(
      this.appProvider(),
      worldDatabase.databaseId,
    );
    if (client.databaseId !== worldDatabase.databaseId) {
      throw new Error(
        "Firestore database route mismatch: " +
        `requested ${worldDatabase.databaseId}, received ${client.databaseId}`,
      );
    }

    this.clients.set(worldDatabase.databaseId, client);
    return client;
  }
}

/**
 * Validates the P00 subset of the future world catalog contract.
 *
 * @param {WorldDatabaseConfig} worldDatabase World database to validate.
 */
function validateWorldDatabase(worldDatabase: WorldDatabaseConfig): void {
  if (worldDatabase.worldId.length === 0 ||
      worldDatabase.worldId.trim() !== worldDatabase.worldId) {
    throw new Error("World ID must be a non-empty trimmed string.");
  }

  assertSupportedDatabaseId(worldDatabase.databaseId);
}

/**
 * Rejects database IDs outside the reviewed application allowlist.
 *
 * @param {string} databaseId Firestore database ID to validate.
 */
function assertSupportedDatabaseId(
  databaseId: string,
): asserts databaseId is WorldFirestoreDatabaseId {
  if (!WORLD_FIRESTORE_DATABASE_ID_SET.has(databaseId)) {
    throw new Error(`Unsupported Firestore database ID: ${databaseId}`);
  }
}
