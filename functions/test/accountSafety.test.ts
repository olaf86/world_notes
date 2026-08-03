/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {DocumentSnapshot, Timestamp} from "firebase-admin/firestore";

import {
  ACCOUNT_SAFETY_BAN_MILLIS,
  ACCOUNT_SAFETY_DECAY_GRACE_MILLIS,
  ACCOUNT_SAFETY_DECAY_INTERVAL_MILLIS,
  ACCOUNT_SAFETY_RESTRICTION_MILLIS,
  applyAdminAction,
  applyAccountSafetyDecay,
  initialAccountSafetyData,
  parseAccountSafetyProjection,
  parseAdminAccountSafetyAction,
} from "../src/accountSafety";

const NOW = Timestamp.fromMillis(Date.UTC(2026, 7, 3));

test("initial account safety permits all operations", () => {
  const initial = initialAccountSafetyData("asia", NOW);

  assert.equal(initial.revision, 1);
  assert.equal(initial.violationPoints, 0);
  assert.equal(initial.restrictedUntil, null);
  assert.equal(initial.bannedUntil, null);
  assert.equal(initial.isPermanentlyBanned, false);
  assert.equal(
    parseAccountSafetyProjection(snapshot(initial), "asia").authorityWorld,
    "asia",
  );
});

test("point decay starts after the grace and first interval", () => {
  const firstDecayAt = Timestamp.fromMillis(
    NOW.toMillis() + ACCOUNT_SAFETY_DECAY_GRACE_MILLIS +
      ACCOUNT_SAFETY_DECAY_INTERVAL_MILLIS,
  );

  assert.deepEqual(
    applyAccountSafetyDecay(
      100,
      firstDecayAt,
      Timestamp.fromMillis(firstDecayAt.toMillis() - 1),
    ),
    {violationPoints: 100, nextPointDecayAt: firstDecayAt},
  );
  const first = applyAccountSafetyDecay(100, firstDecayAt, firstDecayAt);
  assert.equal(first.violationPoints, 94);
  assert.equal(
    first.nextPointDecayAt?.toMillis(),
    firstDecayAt.toMillis() + ACCOUNT_SAFETY_DECAY_INTERVAL_MILLIS,
  );
});

test("point decay catches up once and clears its checkpoint at zero", () => {
  const firstDecayAt = Timestamp.fromMillis(1_000);
  const afterThreeIntervals = Timestamp.fromMillis(
    firstDecayAt.toMillis() + 2 * ACCOUNT_SAFETY_DECAY_INTERVAL_MILLIS,
  );
  const caughtUp = applyAccountSafetyDecay(
    25,
    firstDecayAt,
    afterThreeIntervals,
  );
  assert.equal(caughtUp.violationPoints, 7);
  assert.equal(
    caughtUp.nextPointDecayAt?.toMillis(),
    firstDecayAt.toMillis() + 3 * ACCOUNT_SAFETY_DECAY_INTERVAL_MILLIS,
  );

  const cleared = applyAccountSafetyDecay(
    5,
    firstDecayAt,
    firstDecayAt,
  );
  assert.deepEqual(cleared, {
    violationPoints: 0,
    nextPointDecayAt: null,
  });
});

test("parser rejects effective enforcement that bypasses its sources", () => {
  const invalid = {
    ...initialAccountSafetyData("asia", NOW),
    restrictedUntil: Timestamp.fromMillis(
      NOW.toMillis() + ACCOUNT_SAFETY_RESTRICTION_MILLIS,
    ),
  };
  assert.throws(
    () => parseAccountSafetyProjection(snapshot(invalid)),
    /effective enforcement/,
  );
});

test("parser accepts independent enforcement sources", () => {
  const automatedRestriction = Timestamp.fromMillis(
    NOW.toMillis() + ACCOUNT_SAFETY_RESTRICTION_MILLIS,
  );
  const administratorBan = Timestamp.fromMillis(
    NOW.toMillis() + ACCOUNT_SAFETY_BAN_MILLIS,
  );
  const value = {
    ...initialAccountSafetyData("asia", NOW),
    automatedRestrictedUntil: automatedRestriction,
    restrictedUntil: automatedRestriction,
    adminBannedUntil: administratorBan,
    bannedUntil: administratorBan,
  };

  const parsed = parseAccountSafetyProjection(snapshot(value));
  assert.equal(parsed.restrictedUntil?.isEqual(automatedRestriction), true);
  assert.equal(parsed.bannedUntil?.isEqual(administratorBan), true);
});

test("administrator restriction remains independent from automation", () => {
  const automatedRestriction = Timestamp.fromMillis(
    NOW.toMillis() + ACCOUNT_SAFETY_RESTRICTION_MILLIS,
  );
  const current = parseAccountSafetyProjection(snapshot({
    ...initialAccountSafetyData("asia", NOW),
    automatedRestrictedUntil: automatedRestriction,
    restrictedUntil: automatedRestriction,
  }));
  const set = applyAdminAction(
    current,
    {type: "setRestriction", durationDays: 3},
    NOW,
  );
  assert.equal(
    set.adminRestrictedUntil?.toMillis(),
    NOW.toMillis() + 3 * 24 * 60 * 60 * 1000,
  );

  const cleared = applyAdminAction(set, {type: "clearRestriction"}, NOW);
  assert.equal(cleared.adminRestrictedUntil, null);
  assert.equal(cleared.restrictedUntil?.isEqual(automatedRestriction), true);
});

test("administrator ban and points remain independent", () => {
  const current = initialAccountSafetyData("asia", NOW);
  const banned = applyAdminAction(current, {type: "setPermanentBan"}, NOW);
  const adjusted = applyAdminAction(
    banned,
    {type: "adjustPoints", delta: 25},
    NOW,
  );
  assert.equal(adjusted.violationPoints, 25);
  assert.equal(adjusted.isPermanentlyBanned, true);

  const unbanned = applyAdminAction(adjusted, {type: "clearBan"}, NOW);
  assert.equal(unbanned.violationPoints, 25);
  assert.equal(unbanned.isPermanentlyBanned, false);
});

test("administrator actions accept only documented presets", () => {
  assert.deepEqual(
    parseAdminAccountSafetyAction({type: "setBan", durationDays: 30}),
    {type: "setBan", durationDays: 30},
  );
  assert.throws(
    () => parseAdminAccountSafetyAction({
      type: "setRestriction",
      durationDays: 2,
    }),
    /action is invalid/,
  );
  assert.throws(
    () => parseAdminAccountSafetyAction({type: "adjustPoints", delta: 0}),
    /action is invalid/,
  );
});

function snapshot(data: object): DocumentSnapshot {
  const fields = data as Record<string, unknown>;
  return {
    exists: true,
    data: () => data,
    get: (field: string) => fields[field],
  } as unknown as DocumentSnapshot;
}
