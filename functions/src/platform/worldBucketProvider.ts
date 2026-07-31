import {App, getApp} from "firebase-admin/app";
import {getStorage, Storage} from "firebase-admin/storage";

import {WorldCatalogEntry} from "./worldCatalog";
import {WorldRegistry, WORLD_REGISTRY} from "./worldRegistry";

export type WorldBucket = ReturnType<Storage["bucket"]>;

export type WorldBucketFactory = (
  app: App,
  bucketName: string,
) => WorldBucket;

export interface WorldBucketProviderOptions {
  readonly appProvider?: () => App;
  readonly bucketFactory?: WorldBucketFactory;
}

/**
 * Creates a bucket client for a trusted catalog route.
 *
 * @param {App} app Initialized Admin app.
 * @param {string} bucketName Trusted bucket name.
 * @return {WorldBucket} Storage bucket client.
 */
export function createAdminWorldBucket(
  app: App,
  bucketName: string,
): WorldBucket {
  return getStorage(app).bucket(bucketName);
}

/** Resolves and caches Cloud Storage buckets by trusted world ID. */
export class WorldBucketProvider {
  private readonly buckets = new Map<string, WorldBucket>();
  private readonly appProvider: () => App;
  private readonly bucketFactory: WorldBucketFactory;

  /**
   * Creates a bucket provider.
   *
   * @param {WorldRegistry} registry Trusted world registry.
   * @param {WorldBucketProviderOptions} options Test injection points.
   */
  constructor(
    private readonly registry: WorldRegistry = WORLD_REGISTRY,
    options: WorldBucketProviderOptions = {},
  ) {
    this.appProvider = options.appProvider ?? getApp;
    this.bucketFactory = options.bucketFactory ?? createAdminWorldBucket;
  }

  /**
   * Returns the bucket for a catalogued world.
   *
   * @param {string} worldId Trusted domain world ID.
   * @return {WorldBucket} Matching Storage bucket.
   */
  forWorld(worldId: string): WorldBucket {
    const world = this.registry.requireWorld(worldId);
    const cached = this.buckets.get(world.bucketName);
    if (cached !== undefined) return cached;

    const bucket = this.bucketFactory(this.appProvider(), world.bucketName);
    assertBucketMatchesWorld(bucket, world);
    this.buckets.set(world.bucketName, bucket);
    return bucket;
  }
}

/**
 * Ensures a factory cannot silently return another world's bucket.
 *
 * @param {WorldBucket} bucket Resolved bucket client.
 * @param {WorldCatalogEntry} world Trusted world metadata.
 */
function assertBucketMatchesWorld(
  bucket: WorldBucket,
  world: WorldCatalogEntry,
): void {
  if (bucket.name !== world.bucketName) {
    throw new Error(
      "Storage bucket route mismatch: " +
      `requested ${world.bucketName}, received ${bucket.name}`,
    );
  }
}
