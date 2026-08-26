import {
  CallableOptions,
  CallableRequest,
  HttpsError,
  onCall as firebaseOnCall,
} from "firebase-functions/v2/https";

import {CallableRouteValidator} from "./callableRouteValidator";
import {worldContext, WorldContext} from "./worldContext";
import {
  WORLD_REGISTRY,
} from "./worldRegistry";
import {
  applicationAuditEvent,
  auditOutcomeForError,
  callableAuditContext,
  writeApplicationAudit,
} from "../applicationAudit";

export {HttpsError};

type WorldCallableResult = object | void;
type WorldCallableHandler<T> = (
  request: CallableRequest<T>,
  world: WorldContext,
) => WorldCallableResult | Promise<WorldCallableResult>;

type WorldCallableOptions<T> = CallableOptions<T> & {
  readonly auditAction?: string;
  readonly requireAccountReady?: boolean;
  readonly requireHomeWorld?: boolean;
};

const routeValidator = new CallableRouteValidator();
const regionalFunctionsRegions = [
  ...new Set(
    WORLD_REGISTRY.catalog.worlds.map((world) => world.functionsRegion),
  ),
];

/**
 * Declares a multi-region callable with trusted world-route validation.
 *
 * All regional callables use this export instead of the raw Firebase helper.
 * The response is stamped with the resolved world so clients can reject a
 * response received from an unexpected deployment.
 *
 * @param {CallableOptions<T>} options Callable deployment options.
 * @param {WorldCallableHandler<T>} handler World-aware request handler.
 * @return {CallableFunction} Firebase callable function.
 */
export function onCall<T = unknown>(
  options: WorldCallableOptions<T>,
  handler: WorldCallableHandler<T>,
) {
  const {
    auditAction,
    requireAccountReady = true,
    requireHomeWorld = false,
    ...firebaseOptions
  } = options;
  return firebaseOnCall<T>(
    {...firebaseOptions, region: regionalFunctionsRegions},
    async (request) => {
      const audit = auditAction === undefined ? null :
        callableAuditContext(request, auditAction);
      let resolvedWorldId: string | null = null;
      try {
        const route = routeValidator.requireContentWorld(
          worldIdFromData(request.data),
        );
        const world = worldContext(route.worldId);
        resolvedWorldId = world.worldId;
        if ((requireAccountReady || requireHomeWorld) &&
            request.auth !== undefined) {
          const homeWorld = await requireReadyAccount(request.auth.uid, world);
          if (requireHomeWorld && homeWorld !== world.worldId) {
            throw new HttpsError(
              "failed-precondition",
              "This operation must use the account's home world.",
              {reason: "wrong-home-world", homeWorld},
            );
          }
        }
        const result = await handler(request, world);
        if (audit !== null) {
          writeApplicationAudit(applicationAuditEvent(
            audit,
            "success",
            resolvedWorldId,
          ));
        }
        return {
          ...(result ?? {}),
          worldId: world.worldId,
        };
      } catch (error) {
        if (audit !== null) {
          writeApplicationAudit(applicationAuditEvent(
            audit,
            auditOutcomeForError(error),
            resolvedWorldId,
            error,
          ));
        }
        throw error;
      }
    },
  );
}

/**
 * Requires the caller's revisioned bootstrap marker in the routed world.
 *
 * @param {string} uid Authenticated caller UID.
 * @param {WorldContext} world Trusted routed world dependencies.
 */
async function requireReadyAccount(
  uid: string,
  world: WorldContext,
): Promise<string> {
  const homeAssignment = await world.firestore
    .collection("userHomes")
    .doc(uid)
    .get();
  const homeWorld = homeAssignment.get("world");
  const epoch = homeAssignment.get("epoch");
  let knownHome = false;
  if (typeof homeWorld === "string") {
    try {
      WORLD_REGISTRY.requireWorld(homeWorld);
      knownHome = true;
    } catch {
      knownHome = false;
    }
  }
  if (!homeAssignment.exists ||
      !knownHome ||
      typeof epoch !== "number" ||
      !Number.isInteger(epoch) ||
      epoch <= 0) {
    throw new HttpsError(
      "failed-precondition",
      "This world is still preparing your account.",
      {reason: "world-not-ready", worldId: world.worldId},
    );
  }
  return homeWorld as string;
}

/**
 * Returns an untrusted world ID from callable request data.
 *
 * @param {unknown} data Callable request data.
 * @return {unknown} The untrusted world ID value.
 */
function worldIdFromData(data: unknown): unknown {
  if (typeof data !== "object" || data === null || Array.isArray(data)) {
    return undefined;
  }
  return (data as Record<string, unknown>).worldId;
}
