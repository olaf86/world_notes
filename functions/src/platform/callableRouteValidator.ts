import {HttpsError} from "firebase-functions/v2/https";

import {WorldCatalogEntry} from "./worldCatalog";
import {WorldRegistry, WORLD_REGISTRY} from "./worldRegistry";

/** Validates client world IDs against trusted deployment metadata. */
export class CallableRouteValidator {
  /**
   * Creates a route validator.
   *
   * @param {WorldRegistry} registry Trusted world registry.
   */
  constructor(private readonly registry: WorldRegistry = WORLD_REGISTRY) {}

  /**
   * Validates an explicit request route for a deployed callable.
   *
   * Resource IDs and regions are never accepted from request data.
   *
   * @param {unknown} value Client-provided world ID.
   * @param {string} deployedWorldId World bound to this Function export.
   * @return {WorldCatalogEntry} Trusted matching descriptor.
   */
  requireContentRoute(
    value: unknown,
    deployedWorldId: string,
  ): WorldCatalogEntry {
    if (typeof value !== "string" || value.length === 0) {
      throw new HttpsError("invalid-argument", "worldId is required.");
    }
    if (value !== deployedWorldId) {
      throw new HttpsError(
        "failed-precondition",
        "The request was sent to the wrong world.",
        {requestedWorldId: value, deployedWorldId},
      );
    }

    try {
      return this.registry.requireContentWorld(value);
    } catch {
      throw new HttpsError(
        "failed-precondition",
        "The requested world is not available.",
      );
    }
  }
}
