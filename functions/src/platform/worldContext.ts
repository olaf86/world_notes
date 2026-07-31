import {Firestore} from "firebase-admin/firestore";

import {WorldCatalogEntry} from "./worldCatalog";
import {
  WorldDatabaseConfig,
  WorldFirestoreDatabaseId,
  WorldFirestoreProvider,
} from "./worldFirestoreProvider";
import {WorldBucket, WorldBucketProvider} from "./worldBucketProvider";
import {
  ASIA_WORLD_ID,
  WorldRegistry,
  WORLD_REGISTRY,
} from "./worldRegistry";

/** Aligned regional dependencies for one trusted world. */
export interface WorldContext {
  readonly worldId: string;
  readonly descriptor: WorldCatalogEntry;
  readonly firestore: Firestore;
  readonly bucket: WorldBucket;
}

export interface WorldContextProviderOptions {
  readonly firestoreProvider?: WorldFirestoreProvider;
  readonly bucketProvider?: WorldBucketProvider;
}

/** Creates and caches aligned server dependencies for enabled worlds. */
export class WorldContextProvider {
  private readonly contexts = new Map<string, WorldContext>();
  private readonly firestoreProvider: WorldFirestoreProvider;
  private readonly bucketProvider: WorldBucketProvider;

  /**
   * Creates a provider backed by the trusted catalog.
   *
   * @param {WorldRegistry} registry Trusted world registry.
   * @param {WorldContextProviderOptions} options Dependency injection points.
   */
  constructor(
    private readonly registry: WorldRegistry = WORLD_REGISTRY,
    options: WorldContextProviderOptions = {},
  ) {
    const worldDatabases = registry.catalog.worlds.map((world) => ({
      worldId: world.worldId,
      databaseId: world.databaseId as WorldFirestoreDatabaseId,
    })) satisfies readonly WorldDatabaseConfig[];
    this.firestoreProvider = options.firestoreProvider ??
      new WorldFirestoreProvider(worldDatabases);
    this.bucketProvider = options.bucketProvider ??
      new WorldBucketProvider(registry);
  }

  /**
   * Resolves dependencies only for a content-enabled world.
   *
   * @param {string} worldId Trusted domain world ID.
   * @return {WorldContext} Aligned regional dependencies.
   */
  forContentWorld(worldId: string): WorldContext {
    const descriptor = this.registry.requireContentWorld(worldId);
    const cached = this.contexts.get(worldId);
    if (cached !== undefined) return cached;

    const firestore = this.firestoreProvider.forWorld(worldId);
    const bucket = this.bucketProvider.forWorld(worldId);
    if (firestore.databaseId !== descriptor.databaseId ||
        bucket.name !== descriptor.bucketName) {
      throw new Error(`World dependency route mismatch: ${worldId}`);
    }

    const context = Object.freeze({
      worldId,
      descriptor,
      firestore,
      bucket,
    });
    this.contexts.set(worldId, context);
    return context;
  }
}

let productionProvider: WorldContextProvider | undefined;

/**
 * Resolves the fixed Asia context used by existing Functions during P05.
 *
 * Initialization is lazy because Firebase Admin is initialized by index.ts
 * after module loading.
 *
 * @return {WorldContext} Asia's aligned dependencies.
 */
export function asiaWorldContext(): WorldContext {
  productionProvider ??= new WorldContextProvider();
  return productionProvider.forContentWorld(ASIA_WORLD_ID);
}
