/* eslint-disable require-jsdoc, valid-jsdoc */

export type ProductionPreflightStatus = "pass" | "fail" | "warning";

export interface ProductionPreflightCheck {
  readonly id: string;
  readonly status: ProductionPreflightStatus;
  readonly summary: string;
}

export interface ExpectedWorldResource {
  readonly worldId: string;
  readonly databaseId: string;
  readonly firestoreLocation: string;
  readonly functionsRegion: string;
  readonly bucketName: string;
  readonly firestoreRulesSource: string;
  readonly storageRulesSource: string;
}

export interface ExpectedFunctionDeployment {
  readonly functionId: string;
  readonly region: string;
}

export interface ExpectedTtlPolicy {
  readonly collectionGroup: string;
  readonly fieldPath: string;
}

export interface ProductionPreflightExpectation {
  readonly projectId: string;
  readonly worlds: readonly ExpectedWorldResource[];
  readonly firestoreIndexes: unknown;
  readonly ttlPolicies: readonly ExpectedTtlPolicy[];
  readonly functions: readonly ExpectedFunctionDeployment[];
}

export interface LiveFirestoreDatabase {
  readonly databaseId: string;
  readonly locationId: string | null;
  readonly edition: string | null;
  readonly type: string | null;
  readonly deleteProtectionState: string | null;
  readonly pointInTimeRecoveryEnablement: string | null;
}

export interface LiveBucket {
  readonly bucketName: string;
  readonly location: string | null;
  readonly uniformBucketLevelAccess: boolean | null;
  readonly publicAccessPrevention: string | null;
  readonly publicMembers: readonly string[];
}

export interface LiveFunctionDeployment {
  readonly functionId: string;
  readonly region: string;
  readonly state: string | null;
  readonly serviceAccountEmail: string | null;
}

export interface LiveTtlPolicy extends ExpectedTtlPolicy {
  readonly state: string | null;
}

export interface LivePermissionCheck {
  readonly principalEmail: string;
  readonly permission: string;
  readonly resource: string;
  readonly granted: boolean | null;
}

export interface ProductionPreflightSnapshot {
  readonly projectId: string;
  readonly databases: readonly LiveFirestoreDatabase[];
  readonly firestoreRulesByDatabase: Readonly<Record<string, string>>;
  readonly storageRulesByBucket: Readonly<Record<string, string>>;
  readonly firestoreIndexesByDatabase: Readonly<Record<string, unknown>>;
  readonly ttlPoliciesByDatabase: Readonly<
    Record<string, readonly LiveTtlPolicy[]>
  >;
  readonly backupScheduleCountByDatabase: Readonly<Record<string, number>>;
  readonly buckets: readonly LiveBucket[];
  readonly functions: readonly LiveFunctionDeployment[];
  readonly permissions: readonly LivePermissionCheck[];
}

export interface ProductionPreflightReport {
  readonly projectId: string;
  readonly checkedAt: string;
  readonly checks: readonly ProductionPreflightCheck[];
  readonly passed: boolean;
  readonly failures: number;
  readonly warnings: number;
}

const PUBLIC_IAM_MEMBERS = new Set([
  "allUsers",
  "allAuthenticatedUsers",
]);

export function evaluateProductionPreflight(
  expected: ProductionPreflightExpectation,
  live: ProductionPreflightSnapshot,
  checkedAt = new Date().toISOString(),
): ProductionPreflightReport {
  const checks: ProductionPreflightCheck[] = [];
  addEqualityCheck(
    checks,
    "project.id",
    live.projectId,
    expected.projectId,
    "Live project matches the explicit target.",
  );

  for (const world of expected.worlds) {
    evaluateWorld(checks, expected, live, world);
  }
  evaluateFunctions(checks, expected.functions, live.functions);
  evaluatePermissions(checks, live.permissions);

  const expectedDatabaseIds = new Set(
    expected.worlds.map((world) => world.databaseId),
  );
  const unexpectedDatabases = live.databases
    .map((database) => database.databaseId)
    .filter((databaseId) => !expectedDatabaseIds.has(databaseId));
  if (unexpectedDatabases.length > 0) {
    checks.push({
      id: "firestore.databases.unexpected",
      status: "warning",
      summary: `Unexpected databases: ${unexpectedDatabases.join(", ")}.`,
    });
  }

  const failures = checks.filter((check) => check.status === "fail").length;
  const warnings = checks
    .filter((check) => check.status === "warning").length;
  return Object.freeze({
    projectId: expected.projectId,
    checkedAt,
    checks: Object.freeze(checks),
    passed: failures === 0,
    failures,
    warnings,
  });
}

function evaluateWorld(
  checks: ProductionPreflightCheck[],
  expected: ProductionPreflightExpectation,
  live: ProductionPreflightSnapshot,
  world: ExpectedWorldResource,
): void {
  const prefix = `world.${world.worldId}`;
  const database = live.databases.find(
    (candidate) => candidate.databaseId === world.databaseId,
  );
  if (database === undefined) {
    checks.push({
      id: `${prefix}.database`,
      status: "fail",
      summary: `Database ${world.databaseId} is missing.`,
    });
  } else {
    addEqualityCheck(
      checks,
      `${prefix}.database.location`,
      database.locationId,
      world.firestoreLocation,
      `Database location is ${world.firestoreLocation}.`,
    );
    addEqualityCheck(
      checks,
      `${prefix}.database.edition`,
      database.edition,
      "STANDARD",
      "Database uses Standard edition.",
    );
    addEqualityCheck(
      checks,
      `${prefix}.database.type`,
      database.type,
      "FIRESTORE_NATIVE",
      "Database uses Firestore Native mode.",
    );
    addEqualityCheck(
      checks,
      `${prefix}.database.deleteProtection`,
      database.deleteProtectionState,
      "DELETE_PROTECTION_ENABLED",
      "Database delete protection is enabled.",
    );
    addEqualityCheck(
      checks,
      `${prefix}.database.pitr`,
      database.pointInTimeRecoveryEnablement,
      "POINT_IN_TIME_RECOVERY_ENABLED",
      "Database point-in-time recovery is enabled.",
    );
  }

  addSourceCheck(
    checks,
    `${prefix}.firestoreRules`,
    live.firestoreRulesByDatabase[world.databaseId],
    world.firestoreRulesSource,
  );
  addSourceCheck(
    checks,
    `${prefix}.storageRules`,
    live.storageRulesByBucket[world.bucketName],
    world.storageRulesSource,
  );

  const liveIndexes = live.firestoreIndexesByDatabase[world.databaseId];
  if (liveIndexes === undefined) {
    checks.push({
      id: `${prefix}.firestoreIndexes`,
      status: "fail",
      summary: "Live Firestore indexes could not be read.",
    });
  } else {
    const matches = stableJson(liveIndexes) ===
      stableJson(expected.firestoreIndexes);
    checks.push({
      id: `${prefix}.firestoreIndexes`,
      status: matches ? "pass" : "fail",
      summary: matches ?
        "Live Firestore indexes match the checked-in contract." :
        "Live Firestore indexes differ from the checked-in contract.",
    });
  }

  evaluateTtlPolicies(checks, prefix, expected.ttlPolicies,
    live.ttlPoliciesByDatabase[world.databaseId]);
  const backupScheduleCount =
    live.backupScheduleCountByDatabase[world.databaseId];
  checks.push({
    id: `${prefix}.backupSchedules`,
    status: typeof backupScheduleCount === "number" &&
      backupScheduleCount > 0 ? "pass" : "fail",
    summary: typeof backupScheduleCount === "number" &&
      backupScheduleCount > 0 ?
      `${backupScheduleCount} backup schedule(s) are configured.` :
      "No Firestore backup schedule could be confirmed.",
  });
  evaluateBucket(checks, prefix, world, live.buckets);
}

function evaluateTtlPolicies(
  checks: ProductionPreflightCheck[],
  prefix: string,
  expected: readonly ExpectedTtlPolicy[],
  live: readonly LiveTtlPolicy[] | undefined,
): void {
  if (live === undefined) {
    checks.push({
      id: `${prefix}.ttl`,
      status: "fail",
      summary: "Live TTL policies could not be read.",
    });
    return;
  }
  const expectedKeys = new Set(expected.map(ttlKey));
  const liveKeys = new Set(live
    .filter((policy) => policy.state === "ACTIVE")
    .map(ttlKey));
  const missing = [...expectedKeys].filter((key) => !liveKeys.has(key));
  const unexpected = [...liveKeys].filter((key) => !expectedKeys.has(key));
  checks.push({
    id: `${prefix}.ttl.required`,
    status: missing.length === 0 ? "pass" : "fail",
    summary: missing.length === 0 ?
      "Every checked-in TTL policy is active." :
      `Missing active TTL policies: ${missing.join(", ")}.`,
  });
  if (unexpected.length > 0) {
    checks.push({
      id: `${prefix}.ttl.unexpected`,
      status: "warning",
      summary: `Unexpected active TTL policies: ${unexpected.join(", ")}.`,
    });
  }
}

function evaluateBucket(
  checks: ProductionPreflightCheck[],
  prefix: string,
  world: ExpectedWorldResource,
  liveBuckets: readonly LiveBucket[],
): void {
  const bucket = liveBuckets.find(
    (candidate) => candidate.bucketName === world.bucketName,
  );
  if (bucket === undefined) {
    checks.push({
      id: `${prefix}.bucket`,
      status: "fail",
      summary: `Bucket ${world.bucketName} is missing.`,
    });
    return;
  }
  addEqualityCheck(
    checks,
    `${prefix}.bucket.location`,
    bucket.location?.toLowerCase() ?? null,
    world.firestoreLocation.toLowerCase(),
    `Bucket location is ${world.firestoreLocation}.`,
  );
  addEqualityCheck(
    checks,
    `${prefix}.bucket.uniformAccess`,
    bucket.uniformBucketLevelAccess,
    true,
    "Uniform bucket-level access is enabled.",
  );
  addEqualityCheck(
    checks,
    `${prefix}.bucket.publicAccessPrevention`,
    bucket.publicAccessPrevention,
    "enforced",
    "Public access prevention is enforced.",
  );
  const publicMembers = bucket.publicMembers.filter(
    (member) => PUBLIC_IAM_MEMBERS.has(member),
  );
  checks.push({
    id: `${prefix}.bucket.publicIam`,
    status: publicMembers.length === 0 ? "pass" : "fail",
    summary: publicMembers.length === 0 ?
      "Bucket IAM has no public principals." :
      `Bucket IAM grants public access to ${publicMembers.join(", ")}.`,
  });
}

function evaluateFunctions(
  checks: ProductionPreflightCheck[],
  expected: readonly ExpectedFunctionDeployment[],
  live: readonly LiveFunctionDeployment[],
): void {
  const expectedKeys = new Set(expected.map(functionKey));
  const liveKeys = new Set(live.map(functionKey));
  const missing = [...expectedKeys].filter((key) => !liveKeys.has(key));
  checks.push({
    id: "functions.expectedDeployments",
    status: missing.length === 0 ? "pass" : "fail",
    summary: missing.length === 0 ?
      "Every source function is deployed in its expected region." :
      `Missing function deployments: ${missing.join(", ")}.`,
  });

  const unhealthy = live.filter((deployment) =>
    expectedKeys.has(functionKey(deployment)) &&
    deployment.state !== "ACTIVE");
  checks.push({
    id: "functions.active",
    status: unhealthy.length === 0 ? "pass" : "fail",
    summary: unhealthy.length === 0 ?
      "Every expected deployed function is active." :
      "Inactive expected functions: " +
        unhealthy.map(functionKey).join(", ") + ".",
  });

  const unexpected = [...liveKeys].filter((key) => !expectedKeys.has(key));
  if (unexpected.length > 0) {
    checks.push({
      id: "functions.unexpectedDeployments",
      status: "warning",
      summary: `Unexpected function deployments: ${unexpected.join(", ")}.`,
    });
  }
}

function evaluatePermissions(
  checks: ProductionPreflightCheck[],
  permissions: readonly LivePermissionCheck[],
): void {
  if (permissions.length === 0) {
    checks.push({
      id: "iam.runtimePermissions",
      status: "warning",
      summary: "Runtime IAM permission checks were not available.",
    });
    return;
  }
  const denied = permissions.filter((check) => check.granted === false);
  const unknown = permissions.filter((check) => check.granted === null);
  checks.push({
    id: "iam.runtimePermissions",
    status: denied.length > 0 ? "fail" :
      unknown.length > 0 ? "warning" : "pass",
    summary: denied.length > 0 ?
      "Denied runtime permissions: " +
        denied.map(permissionKey).join(", ") + "." :
      unknown.length > 0 ?
        "Unresolved runtime permissions: " +
          unknown.map(permissionKey).join(", ") + "." :
        "Every tested runtime IAM permission is granted.",
  });
}

function addSourceCheck(
  checks: ProductionPreflightCheck[],
  id: string,
  live: string | undefined,
  expected: string,
): void {
  const matches = live !== undefined && normalizeSource(live) ===
    normalizeSource(expected);
  checks.push({
    id,
    status: matches ? "pass" : "fail",
    summary: matches ?
      "Live rules match the checked-in source." :
      "Live rules differ from the checked-in source or could not be read.",
  });
}

function addEqualityCheck(
  checks: ProductionPreflightCheck[],
  id: string,
  actual: unknown,
  expected: unknown,
  passingSummary: string,
): void {
  const matches = actual === expected;
  checks.push({
    id,
    status: matches ? "pass" : "fail",
    summary: matches ? passingSummary :
      `Expected ${String(expected)}; received ${String(actual)}.`,
  });
}

function normalizeSource(value: string): string {
  return value.replace(/\r\n/g, "\n").trimEnd();
}

function ttlKey(policy: ExpectedTtlPolicy): string {
  return `${policy.collectionGroup}.${policy.fieldPath}`;
}

function functionKey(deployment: ExpectedFunctionDeployment): string {
  return `${deployment.functionId}@${deployment.region}`;
}

function permissionKey(check: LivePermissionCheck): string {
  return `${check.principalEmail}:${check.permission}@${check.resource}`;
}

export function stableJson(value: unknown): string {
  return JSON.stringify(sortJson(value));
}

function sortJson(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(sortJson);
  }
  if (typeof value === "object" && value !== null) {
    const record = value as Record<string, unknown>;
    return Object.fromEntries(Object.keys(record).sort().map((key) => [
      key,
      sortJson(record[key]),
    ]));
  }
  return value;
}
