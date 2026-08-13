/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {
  evaluateProductionPreflight,
  type ProductionPreflightExpectation,
  type ProductionPreflightSnapshot,
} from "../src/productionPreflight";

const EXPECTED: ProductionPreflightExpectation = Object.freeze({
  projectId: "world-notes-prod",
  worlds: Object.freeze([{
    worldId: "asia",
    databaseId: "(default)",
    firestoreLocation: "asia-northeast1",
    functionsRegion: "asia-northeast1",
    bucketName: "world-notes-prod.firebasestorage.app",
    firestoreRulesSource: "rules_version = '2';\nallow read: if true;\n",
    storageRulesSource: "rules_version = '2';\nallow read: if true;\n",
  }]),
  firestoreIndexes: Object.freeze({
    indexes: [{
      collectionGroup: "places",
      queryScope: "COLLECTION",
      fields: [{fieldPath: "expiresAt", order: "ASCENDING"}],
    }],
  }),
  ttlPolicies: Object.freeze([{
    collectionGroup: "jobs",
    fieldPath: "expireAt",
  }]),
  functions: Object.freeze([{
    functionId: "createNote",
    region: "asia-northeast1",
  }]),
});

function passingSnapshot(): ProductionPreflightSnapshot {
  return {
    projectId: "world-notes-prod",
    databases: [{
      databaseId: "(default)",
      locationId: "asia-northeast1",
      edition: "STANDARD",
      type: "FIRESTORE_NATIVE",
      deleteProtectionState: "DELETE_PROTECTION_ENABLED",
      pointInTimeRecoveryEnablement: "POINT_IN_TIME_RECOVERY_ENABLED",
    }],
    firestoreRulesByDatabase: {
      "(default)": "rules_version = '2';\nallow read: if true;",
    },
    storageRulesByBucket: {
      "world-notes-prod.firebasestorage.app":
        "rules_version = '2';\nallow read: if true;",
    },
    firestoreIndexesByDatabase: {
      "(default)": {
        indexes: [{
          fields: [{order: "ASCENDING", fieldPath: "expiresAt"}],
          queryScope: "COLLECTION",
          collectionGroup: "places",
        }],
      },
    },
    ttlPoliciesByDatabase: {
      "(default)": [{
        collectionGroup: "jobs",
        fieldPath: "expireAt",
        state: "ACTIVE",
      }],
    },
    backupScheduleCountByDatabase: {"(default)": 1},
    buckets: [{
      bucketName: "world-notes-prod.firebasestorage.app",
      location: "ASIA-NORTHEAST1",
      uniformBucketLevelAccess: true,
      publicAccessPrevention: "enforced",
      publicMembers: [],
    }],
    functions: [{
      functionId: "createNote",
      region: "asia-northeast1",
      state: "ACTIVE",
      serviceAccountEmail: "runtime@world-notes-prod.iam.gserviceaccount.com",
    }],
    permissions: [{
      principalEmail: "runtime@world-notes-prod.iam.gserviceaccount.com",
      permission: "datastore.entities.get",
      resource: "//cloudresourcemanager.googleapis.com/projects/" +
        "world-notes-prod",
      granted: true,
    }],
  };
}

test("production preflight passes an exact protected deployment", () => {
  const report = evaluateProductionPreflight(
    EXPECTED,
    passingSnapshot(),
    "2026-08-13T00:00:00.000Z",
  );

  assert.equal(report.passed, true);
  assert.equal(report.failures, 0);
  assert.equal(report.warnings, 0);
  assert.equal(report.checkedAt, "2026-08-13T00:00:00.000Z");
});

test("production preflight rejects infrastructure and deployment drift", () => {
  const passing = passingSnapshot();
  const report = evaluateProductionPreflight(EXPECTED, {
    ...passing,
    projectId: "different-project",
    databases: [{
      ...passing.databases[0],
      deleteProtectionState: "DELETE_PROTECTION_DISABLED",
    }],
    firestoreRulesByDatabase: {"(default)": "changed"},
    firestoreIndexesByDatabase: {"(default)": {indexes: []}},
    ttlPoliciesByDatabase: {"(default)": []},
    backupScheduleCountByDatabase: {"(default)": 0},
    buckets: [{
      ...passing.buckets[0],
      publicMembers: ["allUsers"],
    }],
    functions: [{
      ...passing.functions[0],
      state: null,
    }],
    permissions: [{
      ...passing.permissions[0],
      granted: false,
    }],
  });

  assert.equal(report.passed, false);
  for (const id of [
    "project.id",
    "world.asia.database.deleteProtection",
    "world.asia.firestoreRules",
    "world.asia.firestoreIndexes",
    "world.asia.ttl.required",
    "world.asia.backupSchedules",
    "world.asia.bucket.publicIam",
    "functions.active",
    "iam.runtimePermissions",
  ]) {
    assert.equal(
      report.checks.find((check) => check.id === id)?.status,
      "fail",
      id,
    );
  }
});

test("production preflight reports unconfirmed and unexpected state", () => {
  const passing = passingSnapshot();
  const report = evaluateProductionPreflight(EXPECTED, {
    ...passing,
    databases: [
      ...passing.databases,
      {
        ...passing.databases[0],
        databaseId: "unexpected",
      },
    ],
    ttlPoliciesByDatabase: {
      "(default)": [
        ...passing.ttlPoliciesByDatabase["(default)"],
        {
          collectionGroup: "other",
          fieldPath: "deleteAt",
          state: "ACTIVE",
        },
      ],
    },
    functions: [
      ...passing.functions,
      {
        functionId: "oldFunction",
        region: "us-central1",
        state: "ACTIVE",
        serviceAccountEmail: null,
      },
    ],
    permissions: [],
  });

  assert.equal(report.passed, true);
  assert.deepEqual(
    report.checks
      .filter((check) => check.status === "warning")
      .map((check) => check.id)
      .sort(),
    [
      "firestore.databases.unexpected",
      "functions.unexpectedDeployments",
      "iam.runtimePermissions",
      "world.asia.ttl.unexpected",
    ],
  );
});
