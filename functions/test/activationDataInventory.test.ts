/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {
  evaluateActivationDataInventory,
  type WorldActivationDataCounts,
} from "../src/activationDataInventory";
import {
  parseActivationInventoryArgs,
} from "../src/scripts/inventoryActivationData";

function world(
  worldId: string,
  overrides: Partial<WorldActivationDataCounts> = {},
): WorldActivationDataCounts {
  return {
    worldId,
    userHomes: 2,
    privateUsers: worldId === "asia" ? 2 : 0,
    publicProfiles: 2,
    userEntitlements: 2,
    userUsage: worldId === "asia" ? 2 : 0,
    accountSafety: 2,
    socialEdges: 1,
    blockedUsers: 1,
    places: worldId === "asia" ? 3 : 0,
    pendingGlobalOperations: 0,
    failedGlobalOperations: 0,
    ...overrides,
  };
}

test("activation data inventory accepts converged mirror-only worlds", () => {
  const result = evaluateActivationDataInventory([
    world("asia"),
    world("northAmerica"),
    world("europe"),
  ], {
    contentAccessWorldIds: new Set(["asia"]),
    homeAssignmentWorldIds: new Set(["asia"]),
  });
  assert.equal(result.pass, true);
  assert.equal(result.checks.every((check) => check.pass), true);
});

test("activation data inventory reports mirror and backlog drift", () => {
  const result = evaluateActivationDataInventory([
    world("asia"),
    world("northAmerica", {socialEdges: 0, places: 1}),
    world("europe", {pendingGlobalOperations: 1}),
  ], {
    contentAccessWorldIds: new Set(["asia"]),
    homeAssignmentWorldIds: new Set(["asia"]),
  });
  assert.equal(result.pass, false);
  assert.deepEqual(
    result.checks.filter((check) => !check.pass).map((check) => check.code),
    [
      "northAmerica.socialEdges.matchesAsia",
      "northAmerica.places.emptyBeforeContentAccess",
      "europe.pendingGlobalOperations.empty",
    ],
  );
});

test("activation data inventory permits content in an enabled world", () => {
  const result = evaluateActivationDataInventory([
    world("asia"),
    world("northAmerica", {userUsage: 1, places: 1}),
    world("europe"),
  ], {
    contentAccessWorldIds: new Set(["asia", "northAmerica"]),
    homeAssignmentWorldIds: new Set(["asia"]),
  });

  assert.equal(result.pass, true);
  assert.equal(
    result.checks.some((check) => check.code.startsWith(
      "northAmerica.places.empty",
    )),
    false,
  );
  assert.equal(
    result.checks.some((check) =>
      check.code === "europe.places.emptyBeforeContentAccess"),
    true,
  );
});

test("activation data inventory permits authority in a home world", () => {
  const result = evaluateActivationDataInventory([
    world("asia"),
    world("northAmerica", {privateUsers: 1, userUsage: 1, places: 1}),
    world("europe"),
  ], {
    contentAccessWorldIds: new Set(["asia", "northAmerica"]),
    homeAssignmentWorldIds: new Set(["asia", "northAmerica"]),
  });

  assert.equal(result.pass, true);
  assert.equal(
    result.checks.some((check) =>
      check.code === "northAmerica.privateUsers.empty"),
    false,
  );
});

test("activation inventory requires one explicit valid project", () => {
  assert.throws(() => parseActivationInventoryArgs([]));
  assert.deepEqual(parseActivationInventoryArgs([
    "--project", "world-notes-prod",
    "--report", "/tmp/inventory.json",
  ]), {
    projectId: "world-notes-prod",
    reportPath: "/tmp/inventory.json",
  });
});
