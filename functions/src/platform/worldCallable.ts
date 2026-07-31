import {
  CallableOptions,
  CallableRequest,
  HttpsError,
  onCall as firebaseOnCall,
} from "firebase-functions/v2/https";

import {CallableRouteValidator} from "./callableRouteValidator";
import {asiaWorldContext, WorldContext} from "./worldContext";
import {ASIA_WORLD, ASIA_WORLD_ID} from "./worldRegistry";

export {HttpsError};

type WorldCallableResult = object | void;
type WorldCallableHandler<T> = (
  request: CallableRequest<T>,
  world: WorldContext,
) => WorldCallableResult | Promise<WorldCallableResult>;

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
  options: CallableOptions<T>,
  handler: WorldCallableHandler<T>,
) {
  return firebaseOnCall<T>(
    {...options, region: ASIA_WORLD.functionsRegion},
    async (request) => {
      routeValidator.requireContentRoute(
        worldIdFromData(request.data),
        ASIA_WORLD_ID,
      );
      const result = await handler(request, asiaWorldContext());
      return {
        ...(result ?? {}),
        worldId: ASIA_WORLD_ID,
      };
    },
  );
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
