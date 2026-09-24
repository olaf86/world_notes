import assert from "node:assert/strict";
import test from "node:test";

import {
  legalAcceptanceFields,
  legalAcceptanceFrom,
} from "../src/legalPolicy";

test("accepts only the current complete legal acknowledgement", () => {
  const acceptance = legalAcceptanceFrom({
    serviceTermsVersion: "2026-09-22",
    privacyPolicyVersion: "2026-09-24",
    locale: "ja",
  });
  assert.deepEqual(acceptance, {locale: "ja"});
  if (acceptance === null) assert.fail("Expected legal acceptance.");
  assert.deepEqual(legalAcceptanceFields(acceptance, "now"), {
    serviceTermsAcceptedVersion: "2026-09-22",
    serviceTermsAcceptedAt: "now",
    privacyPolicyAcknowledgedVersion: "2026-09-24",
    privacyPolicyAcknowledgedAt: "now",
    legalAcceptanceLocale: "ja",
  });
});

test("allows a fully omitted acknowledgement only for legacy bootstrap", () => {
  assert.equal(legalAcceptanceFrom(undefined, true), null);
  assert.throws(() => legalAcceptanceFrom(undefined));
});

test("rejects stale or partial acknowledgements", () => {
  assert.throws(() => legalAcceptanceFrom({
    serviceTermsVersion: "2026-09-22",
    locale: "en",
  }, true));
  assert.throws(() => legalAcceptanceFrom({
    serviceTermsVersion: "2026-01-01",
    privacyPolicyVersion: "2026-09-24",
    locale: "en",
  }));
});
