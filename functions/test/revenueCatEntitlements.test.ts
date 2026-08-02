/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {
  parseRevenueCatEntitlement,
  requireRevenueCatPlatform,
  RevenueCatResponseError,
} from "../src/revenueCatEntitlements";

const NOW = Date.parse("2026-08-02T00:00:00Z");

test("RevenueCat lifetime entitlement is active", () => {
  const status = parseRevenueCatEntitlement(customerInfo({
    expires_date: null,
    grace_period_expires_date: null,
  }));

  assert.equal(status.isPremium, true);
  assert.equal(status.checkedAt.toMillis(), NOW);
});

test("RevenueCat entitlement remains active through its grace period", () => {
  const status = parseRevenueCatEntitlement(customerInfo({
    expires_date: "2026-08-01T00:00:00Z",
    grace_period_expires_date: "2026-08-03T00:00:00Z",
  }));

  assert.equal(status.isPremium, true);
});

test("RevenueCat missing or expired entitlement is inactive", () => {
  assert.equal(
    parseRevenueCatEntitlement(customerInfo(undefined)).isPremium,
    false,
  );
  assert.equal(
    parseRevenueCatEntitlement(customerInfo({
      expires_date: "2026-08-01T00:00:00Z",
      grace_period_expires_date: null,
    })).isPremium,
    false,
  );
});

test("RevenueCat malformed CustomerInfo is rejected", () => {
  assert.throws(
    () => parseRevenueCatEntitlement({request_date_ms: NOW}),
    RevenueCatResponseError,
  );
  assert.throws(
    () => parseRevenueCatEntitlement(customerInfo({
      expires_date: "not-a-date",
      grace_period_expires_date: null,
    })),
    RevenueCatResponseError,
  );
});

test("RevenueCat platform accepts only configured mobile apps", () => {
  assert.equal(requireRevenueCatPlatform("ios"), "ios");
  assert.equal(requireRevenueCatPlatform("android"), "android");
  assert.throws(() => requireRevenueCatPlatform("web"));
});

function customerInfo(
  entitlement: Record<string, unknown> | undefined,
): Record<string, unknown> {
  return {
    request_date_ms: NOW,
    subscriber: {
      entitlements: entitlement === undefined ? {} : {pro: entitlement},
    },
  };
}
