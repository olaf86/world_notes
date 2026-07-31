import {
  CallableOptions,
  CallableRequest,
  HttpsError,
  onCall as firebaseOnCall,
} from "firebase-functions/v2/https";

import {CallableRouteValidator} from "./callableRouteValidator";
import {asiaWorldContext, WorldContext} from "./worldContext";
import {
  ASIA_WORLD,
  ASIA_WORLD_ID,
  WORLD_REGISTRY,
} from "./worldRegistry";

export {HttpsError};

type WorldCallableResult = object | void;
type WorldCallableHandler<T> = (
  request: CallableRequest<T>,
  world: WorldContext,
) => WorldCallableResult | Promise<WorldCallableResult>;

type WorldCallableOptions<T> = CallableOptions<T> & {
  readonly requireAccountReady?: boolean;
};

const routeValidator = new CallableRouteValidator();

/**
 * Declares an Asia callable with mandatory trusted world-route validation.
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
    requireAccountReady = true,
    ...firebaseOptions
  } = options;
  return firebaseOnCall<T>(
    {...firebaseOptions, region: ASIA_WORLD.functionsRegion},
    async (request) => {
      routeValidator.requireContentRoute(
        worldIdFromData(request.data),
        ASIA_WORLD_ID,
      );
      const world = asiaWorldContext();
      if (requireAccountReady && request.auth !== undefined) {
        await assertAccountReady(request.auth.uid, world);
      }
      const result = await handler(request, world);
      return {
        ...(result ?? {}),
        worldId: ASIA_WORLD_ID,
      };
    },
  );
}

/**
 * Requires the caller's revisioned bootstrap marker in the routed world.
 *
 * @param {string} uid Authenticated caller UID.
 * @param {WorldContext} world Trusted routed world dependencies.
 */
async function assertAccountReady(
  uid: string,
  world: WorldContext,
): Promise<void> {
  const marker = await world.firestore.collection("userHomes").doc(uid).get();
  const homeWorld = marker.get("world");
  const epoch = marker.get("epoch");
  let knownHome = false;
  if (typeof homeWorld === "string") {
    try {
      WORLD_REGISTRY.requireWorld(homeWorld);
      knownHome = true;
    } catch {
      knownHome = false;
    }
  }
  if (!marker.exists ||
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
