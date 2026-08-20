import {
  WORLD_CATALOG,
  WorldCatalog,
  WorldCatalogEntry,
} from "./worldCatalog";

/** Trusted identifier of the initial production world. */
export const ASIA_WORLD_ID = "asia";

/** Resolves reviewed world metadata without accepting resource names. */
export class WorldRegistry {
  private readonly worlds = new Map<string, WorldCatalogEntry>();

  /**
   * Builds a registry from a validated catalog.
   *
   * @param {WorldCatalog} catalog Trusted catalog.
   */
  constructor(readonly catalog: WorldCatalog = WORLD_CATALOG) {
    for (const world of catalog.worlds) {
      this.worlds.set(world.worldId, world);
    }
  }

  /**
   * Resolves any catalogued world.
   *
   * @param {string} worldId Trusted domain world ID.
   * @return {WorldCatalogEntry} World metadata.
   */
  requireWorld(worldId: string): WorldCatalogEntry {
    const world = this.worlds.get(worldId);
    if (world === undefined) {
      throw new Error(`Unknown world ID: ${worldId}`);
    }
    return world;
  }

  /**
   * Resolves only a world currently open for content access.
   *
   * @param {string} worldId Trusted domain world ID.
   * @return {WorldCatalogEntry} Enabled world metadata.
   */
  requireContentWorld(worldId: string): WorldCatalogEntry {
    const world = this.requireWorld(worldId);
    if (!world.contentAccessEnabled) {
      throw new Error(`World is not enabled for content access: ${worldId}`);
    }
    return world;
  }

  /**
   * Resolves only a world that may receive a new immutable home assignment.
   *
   * @param {string} worldId Trusted domain world ID.
   * @return {WorldCatalogEntry} Home-enabled world metadata.
   */
  requireHomeWorld(worldId: string): WorldCatalogEntry {
    const world = this.requireContentWorld(worldId);
    if (!world.homeAssignmentEnabled) {
      throw new Error(`World is not enabled for home assignment: ${worldId}`);
    }
    return world;
  }
}

export const WORLD_REGISTRY = new WorldRegistry();
export const ASIA_WORLD = WORLD_REGISTRY.requireContentWorld(ASIA_WORLD_ID);
