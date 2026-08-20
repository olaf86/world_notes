/* eslint-disable valid-jsdoc */

import {Timestamp} from "firebase-admin/firestore";
import {defineSecret} from "firebase-functions/params";

import {
  GlobalOperationBindingError,
  GlobalOperationValidationError,
} from "./globalOperations";
import {onCall, HttpsError} from "./platform/worldCallable";
import {executeEntitlementUpdate} from "./profileEntitlementReplication";

const REVENUECAT_API_ORIGIN = "https://api.revenuecat.com";
const PRO_ENTITLEMENT_ID = "pro";
const REQUEST_TIMEOUT_MILLIS = 10_000;

// These are RevenueCat app-specific public SDK keys. Keeping separate names
// prevents an iOS key from being mistaken for the Android app key.
export const REVENUECAT_PUBLIC_API_KEY_IOS = defineSecret(
  "REVENUECAT_PUBLIC_API_KEY_IOS",
);
export const REVENUECAT_PUBLIC_API_KEY_ANDROID = defineSecret(
  "REVENUECAT_PUBLIC_API_KEY_ANDROID",
);

export type RevenueCatPlatform = "ios" | "android";

interface RefreshEntitlementData {
  readonly operationId?: unknown;
  readonly platform?: unknown;
}

export interface RevenueCatEntitlementStatus {
  readonly isPremium: boolean;
  readonly checkedAt: Timestamp;
}

/**
 * Refreshes the signed-in user's entitlement from RevenueCat at home authority.
 *
 * The client supplies only an idempotency key. The entitlement value always
 * comes from RevenueCat's authenticated server response.
 */
export const refreshEntitlement = onCall<RefreshEntitlementData>(
  {
    enforceAppCheck: true,
    secrets: [
      REVENUECAT_PUBLIC_API_KEY_IOS,
      REVENUECAT_PUBLIC_API_KEY_ANDROID,
    ],
  },
  async (request, world) => {
    const uid = request.auth?.uid;
    if (uid === undefined) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }

    try {
      const platform = requireRevenueCatPlatform(request.data?.platform);
      const status = await fetchRevenueCatEntitlement(
        uid,
        revenueCatApiKey(platform),
      );
      const operation = await executeEntitlementUpdate({
        firestore: world.firestore,
        authorityWorld: world.worldId,
        uid,
        operationId: request.data?.operationId,
        isPremium: status.isPremium,
        sourceCheckedAt: status.checkedAt,
        sourceEventId: "revenueCatCustomerInfo",
      });
      return {isPremium: status.isPremium, ...operation};
    } catch (error) {
      if (error instanceof GlobalOperationBindingError) {
        throw new HttpsError(
          "already-exists",
          "operationId is already bound to another command.",
        );
      }
      if (error instanceof GlobalOperationValidationError) {
        throw new HttpsError("invalid-argument", error.message);
      }
      if (error instanceof RevenueCatResponseError) {
        throw new HttpsError(
          "unavailable",
          "Subscription status could not be verified.",
          {reason: error.code},
        );
      }
      throw error;
    }
  },
);

/** Selects the public SDK key belonging to the calling app platform. */
function revenueCatApiKey(platform: RevenueCatPlatform): string {
  return platform === "ios" ?
    REVENUECAT_PUBLIC_API_KEY_IOS.value() :
    REVENUECAT_PUBLIC_API_KEY_ANDROID.value();
}

/** Rejects platform values outside the two configured mobile apps. */
export function requireRevenueCatPlatform(
  value: unknown,
): RevenueCatPlatform {
  if (value !== "ios" && value !== "android") {
    throw new GlobalOperationValidationError(
      "RevenueCat platform must be ios or android.",
    );
  }
  return value;
}

/** Fetches the latest server-authoritative RevenueCat CustomerInfo. */
export async function fetchRevenueCatEntitlement(
  uid: string,
  apiKey: string,
): Promise<RevenueCatEntitlementStatus> {
  if (apiKey.length === 0) {
    throw new RevenueCatResponseError("api-key-missing");
  }
  let response: Response;
  try {
    response = await fetch(
      `${REVENUECAT_API_ORIGIN}/v1/subscribers/${encodeURIComponent(uid)}`,
      {
        headers: {Authorization: `Bearer ${apiKey}`},
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MILLIS),
      },
    );
  } catch {
    throw new RevenueCatResponseError("request-failed");
  }
  if (response.status !== 200 && response.status !== 201) {
    throw new RevenueCatResponseError(`http-${response.status}`);
  }
  let body: unknown;
  try {
    body = await response.json();
  } catch {
    throw new RevenueCatResponseError("invalid-json");
  }
  return parseRevenueCatEntitlement(body);
}

/** Derives active PRO state using RevenueCat's own response timestamp. */
export function parseRevenueCatEntitlement(
  value: unknown,
): RevenueCatEntitlementStatus {
  const body = requireRecord(value, "response");
  const requestDateMillis = body.request_date_ms;
  if (typeof requestDateMillis !== "number" ||
      !Number.isSafeInteger(requestDateMillis) ||
      requestDateMillis <= 0) {
    throw new RevenueCatResponseError("invalid-request-date");
  }
  const subscriber = requireRecord(body.subscriber, "subscriber");
  const entitlements = requireRecord(
    subscriber.entitlements,
    "subscriber.entitlements",
  );
  const entitlement = entitlements[PRO_ENTITLEMENT_ID];
  return Object.freeze({
    isPremium: entitlement === undefined ?
      false :
      entitlementIsActive(entitlement, requestDateMillis),
    checkedAt: Timestamp.fromMillis(requestDateMillis),
  });
}

/** RevenueCat response fault stored only as a bounded callable reason. */
export class RevenueCatResponseError extends Error {
  /** Creates a provider response error with a bounded machine-readable code. */
  constructor(readonly code: string) {
    super(`RevenueCat response error: ${code}.`);
    this.name = "RevenueCatResponseError";
  }
}

/** Checks ordinary expiry and billing grace-period expiry. */
function entitlementIsActive(
  value: unknown,
  requestDateMillis: number,
): boolean {
  const entitlement = requireRecord(value, "entitlement");
  const expiresAt = optionalIsoDate(entitlement.expires_date, "expires_date");
  const graceExpiresAt = optionalIsoDate(
    entitlement.grace_period_expires_date,
    "grace_period_expires_date",
  );
  if (expiresAt === null) return true;
  return Math.max(expiresAt, graceExpiresAt ?? 0) > requestDateMillis;
}

/** Requires one ordinary JSON object. */
function requireRecord(value: unknown, field: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new RevenueCatResponseError(`invalid-${field}`);
  }
  return value as Record<string, unknown>;
}

/** Parses an explicit nullable RevenueCat ISO-8601 date. */
function optionalIsoDate(value: unknown, field: string): number | null {
  if (value === null) return null;
  if (typeof value !== "string") {
    throw new RevenueCatResponseError(`invalid-${field}`);
  }
  const parsed = Date.parse(value);
  if (!Number.isFinite(parsed)) {
    throw new RevenueCatResponseError(`invalid-${field}`);
  }
  return parsed;
}
