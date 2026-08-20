/* eslint-disable require-jsdoc, no-console */

import {spawnSync} from "node:child_process";
import {readFile, writeFile} from "node:fs/promises";
import {resolve} from "node:path";

import {deleteApp, getApps} from "firebase-admin/app";

import * as productionFunctions from "../index";
import {
  evaluateProductionPreflight,
  type ExpectedFunctionDeployment,
  type ExpectedTtlPolicy,
  type ExpectedWorldResource,
  type LiveBucket,
  type LiveFirestoreDatabase,
  type LiveFunctionDeployment,
  type LivePermissionCheck,
  type LiveTtlPolicy,
  type ProductionPreflightExpectation,
  type ProductionPreflightReport,
  type ProductionPreflightSnapshot,
  stableJson,
} from "../productionPreflight";
import {WORLD_CATALOG} from "../platform/worldCatalog";

const FIREBASE_TOOLS_VERSION = "15.25.1";
const PROJECT_ID_PATTERN = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/;
const REPO_ROOT = `${resolve(__dirname, "../../..")}/`;

interface ParsedArgs {
  readonly projectId: string;
  readonly reportPath: string | null;
  readonly skipIam: boolean;
}

interface FirebaseConfig {
  readonly firestore: readonly Readonly<{
    database: string;
    rules: string;
    indexes: string;
  }>[];
  readonly storage: readonly Readonly<{
    target: string;
    rules: string;
  }>[];
}

interface FirebaseRc {
  readonly projects: Readonly<Record<string, string>>;
  readonly targets: Readonly<Record<string, Readonly<{
    storage: Readonly<Record<string, readonly string[]>>;
  }>>>;
}

interface RulesRelease {
  readonly name: string;
  readonly rulesetName: string;
}

interface EndpointShape {
  readonly region?: readonly string[] | string;
}

function usage(): string {
  return [
    "Usage:",
    "  npm run preflight:production -- --project <project-id>",
    "  npm run preflight:production -- --project <project-id> --report <path>",
    "  npm run preflight:production -- --project <project-id> --skip-iam",
    "",
    "This command is read-only. It never deploys or changes cloud resources.",
  ].join("\n");
}

function parseArgs(argv: readonly string[]): ParsedArgs {
  let projectId: string | null = null;
  let reportPath: string | null = null;
  let skipIam = false;
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--project") {
      projectId = argv[++index] ?? null;
    } else if (arg === "--report") {
      reportPath = argv[++index] ?? null;
    } else if (arg === "--skip-iam") {
      skipIam = true;
    } else {
      throw new Error(`Unknown argument: ${arg}\n\n${usage()}`);
    }
  }
  if (projectId === null || !PROJECT_ID_PATTERN.test(projectId)) {
    throw new Error(`--project is required and invalid.\n\n${usage()}`);
  }
  if (reportPath === "") {
    throw new Error(`--report requires a path.\n\n${usage()}`);
  }
  return Object.freeze({projectId, reportPath, skipIam});
}

async function readJson(path: string): Promise<unknown> {
  return JSON.parse(await readFile(path, "utf8")) as unknown;
}

async function buildExpectation(
  projectId: string,
): Promise<ProductionPreflightExpectation> {
  const firebaseConfig = await readJson(`${REPO_ROOT}firebase.json`) as
    FirebaseConfig;
  const firebaseRc = await readJson(`${REPO_ROOT}.firebaserc`) as FirebaseRc;
  if (firebaseRc.projects.default !== projectId) {
    throw new Error(
      `Explicit project ${projectId} does not match .firebaserc default ` +
      `${String(firebaseRc.projects.default)}.`,
    );
  }
  const projectTargets = firebaseRc.targets[projectId]?.storage;
  if (projectTargets === undefined) {
    throw new Error(`Storage targets are missing for project ${projectId}.`);
  }

  const firestoreByDatabase = new Map(firebaseConfig.firestore.map((entry) =>
    [entry.database, entry] as const));
  const storageRuleByBucket = new Map<string, string>();
  for (const storage of firebaseConfig.storage) {
    const buckets = projectTargets[storage.target];
    if (!Array.isArray(buckets) || buckets.length !== 1) {
      throw new Error(
        `Storage target ${storage.target} must bind exactly one bucket.`,
      );
    }
    storageRuleByBucket.set(buckets[0], storage.rules);
  }

  const worlds: ExpectedWorldResource[] = [];
  let commonIndexPath: string | null = null;
  for (const world of WORLD_CATALOG.worlds) {
    const firestore = firestoreByDatabase.get(world.databaseId);
    if (firestore === undefined) {
      throw new Error(`Missing firebase.json database ${world.databaseId}.`);
    }
    if (commonIndexPath === null) commonIndexPath = firestore.indexes;
    if (firestore.indexes !== commonIndexPath) {
      throw new Error("Every world must use the shared Firestore indexes.");
    }
    const storageRulesPath = storageRuleByBucket.get(world.bucketName);
    if (storageRulesPath === undefined) {
      throw new Error(`Missing Storage target for ${world.bucketName}.`);
    }
    worlds.push(Object.freeze({
      worldId: world.worldId,
      databaseId: world.databaseId,
      firestoreLocation: world.firestoreLocation,
      functionsRegion: world.functionsRegion,
      bucketName: world.bucketName,
      firestoreRulesSource: await readFile(
        `${REPO_ROOT}${firestore.rules}`,
        "utf8",
      ),
      storageRulesSource: await readFile(
        `${REPO_ROOT}${storageRulesPath}`,
        "utf8",
      ),
    }));
  }
  if (commonIndexPath === null) throw new Error("No Firestore indexes found.");
  const rawIndexConfig = await readJson(`${REPO_ROOT}${commonIndexPath}`);
  const indexConfig = normalizeIndexConfig(rawIndexConfig);
  return Object.freeze({
    projectId,
    worlds: Object.freeze(worlds),
    firestoreIndexes: indexConfig,
    ttlPolicies: Object.freeze(ttlPolicies(rawIndexConfig)),
    functions: Object.freeze(expectedFunctions()),
  });
}

async function collectSnapshot(
  expected: ProductionPreflightExpectation,
  skipIam: boolean,
): Promise<ProductionPreflightSnapshot> {
  const projectId = expected.projectId;
  const databaseList = unwrapResult(runFirebaseJson([
    "firestore:databases:list",
    "--project",
    projectId,
  ]));
  const listedDatabaseIds = records(databaseList).map(databaseIdFromRecord);
  const databases: LiveFirestoreDatabase[] = [];
  const firestoreIndexesByDatabase: Record<string, unknown> = {};
  const ttlPoliciesByDatabase: Record<string, readonly LiveTtlPolicy[]> = {};
  const backupScheduleCountByDatabase: Record<string, number> = {};
  for (const world of expected.worlds) {
    if (!listedDatabaseIds.includes(world.databaseId)) continue;
    databases.push(normalizeDatabase(unwrapResult(runFirebaseJson([
      "firestore:databases:get",
      world.databaseId,
      "--project",
      projectId,
    ])), world.databaseId));
    firestoreIndexesByDatabase[world.databaseId] = normalizeIndexConfig(
      unwrapResult(runFirebaseJson([
        "firestore:indexes",
        "--database",
        world.databaseId,
        "--project",
        projectId,
      ])),
    );
    ttlPoliciesByDatabase[world.databaseId] = normalizeTtlPolicies(
      runGcloudJson([
        "firestore",
        "fields",
        "ttls",
        "list",
        `--database=${world.databaseId}`,
        `--project=${projectId}`,
      ]),
    );
    const schedules = unwrapResult(runFirebaseJson([
      "firestore:backups:schedules:list",
      "--database",
      world.databaseId,
      "--project",
      projectId,
    ]));
    backupScheduleCountByDatabase[world.databaseId] = records(schedules).length;
  }

  let rules: Readonly<{
    firestore: Record<string, string>;
    storage: Record<string, string>;
  }> = Object.freeze({firestore: {}, storage: {}});
  try {
    rules = await collectRules(expected);
  } catch (error) {
    console.warn(
      "[WARN] Live Firebase Rules could not be read: " +
      errorMessage(error),
    );
  }
  const buckets = expected.worlds.map((world) =>
    collectBucket(projectId, world.bucketName));
  const functions = normalizeFunctions(runGcloudJson([
    "functions",
    "list",
    "--v2",
    `--project=${projectId}`,
  ]));
  const permissions = skipIam ? [] : collectPermissions(
    projectId,
    functions,
    expected.worlds.map((world) => world.bucketName),
  );
  return Object.freeze({
    projectId,
    databases: Object.freeze(databases),
    firestoreRulesByDatabase: Object.freeze(rules.firestore),
    storageRulesByBucket: Object.freeze(rules.storage),
    firestoreIndexesByDatabase: Object.freeze(firestoreIndexesByDatabase),
    ttlPoliciesByDatabase: Object.freeze(ttlPoliciesByDatabase),
    backupScheduleCountByDatabase:
      Object.freeze(backupScheduleCountByDatabase),
    buckets: Object.freeze(buckets),
    functions: Object.freeze(functions),
    permissions: Object.freeze(permissions),
  });
}

function runFirebaseJson(args: readonly string[]): unknown {
  return runJson("npx", [
    "-y",
    `firebase-tools@${FIREBASE_TOOLS_VERSION}`,
    ...args,
    "--json",
  ]);
}

function runGcloudJson(args: readonly string[]): unknown {
  return runJson("gcloud", [...args, "--format=json", "--quiet"]);
}

function runJson(command: string, args: readonly string[]): unknown {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    env: {
      ...process.env,
      CLOUDSDK_CORE_DISABLE_PROMPTS: "1",
    },
    maxBuffer: 20 * 1024 * 1024,
  });
  if (result.error !== undefined) throw result.error;
  if (result.status !== 0) {
    throw new Error(
      `${command} ${args.join(" ")} failed: ${result.stderr.trim()}`,
    );
  }
  const stdout = result.stdout.trim();
  return stdout.length === 0 ? [] : JSON.parse(stdout) as unknown;
}

function unwrapResult(value: unknown): unknown {
  const record = asRecord(value);
  return record?.result ?? value;
}

function records(value: unknown): Record<string, unknown>[] {
  if (Array.isArray(value)) return value.map(requireRecord);
  const record = asRecord(value);
  if (record === null) return [];
  for (const key of ["databases", "indexes", "schedules", "backupSchedules"]) {
    if (Array.isArray(record[key])) {
      return (record[key] as unknown[]).map(requireRecord);
    }
  }
  return [record];
}

function databaseIdFromRecord(record: Record<string, unknown>): string {
  const raw = stringValue(record.databaseId) ?? stringValue(record.name);
  if (raw === null) throw new Error("Firestore database ID is missing.");
  return raw.split("/").at(-1) ?? raw;
}

function normalizeDatabase(
  value: unknown,
  expectedDatabaseId: string,
): LiveFirestoreDatabase {
  const record = records(value)[0];
  if (record === undefined) {
    throw new Error(`Firestore database ${expectedDatabaseId} is missing.`);
  }
  const databaseId = databaseIdFromRecord(record);
  if (databaseId !== expectedDatabaseId) {
    throw new Error(
      `Expected database ${expectedDatabaseId}; received ${databaseId}.`,
    );
  }
  return Object.freeze({
    databaseId,
    locationId: stringValue(record.locationId),
    edition: normalizeEnum(
      stringValue(record.edition) ?? stringValue(record.databaseEdition),
    ),
    type: normalizeEnum(stringValue(record.type)),
    deleteProtectionState: normalizeEnum(
      stringValue(record.deleteProtectionState),
    ),
    pointInTimeRecoveryEnablement: normalizeEnum(
      stringValue(record.pointInTimeRecoveryEnablement),
    ),
  });
}

function normalizeIndexConfig(value: unknown): unknown {
  const record = requireRecord(unwrapResult(value));
  const indexes = arrayValue(record.indexes).map((raw) => {
    const index = requireRecord(raw);
    return {
      collectionGroup: stringValue(index.collectionGroup),
      queryScope: stringValue(index.queryScope) ?? "COLLECTION",
      fields: arrayValue(index.fields).map((rawField) => {
        const field = requireRecord(rawField);
        return Object.fromEntries([
          ["fieldPath", stringValue(field.fieldPath)],
          ...(stringValue(field.order) === null ? [] :
            [["order", stringValue(field.order)]]),
          ...(stringValue(field.arrayConfig) === null ? [] :
            [["arrayConfig", stringValue(field.arrayConfig)]]),
        ]);
      }).filter((field) => field.fieldPath !== "__name__"),
    };
  }).sort(compareStableJson);
  return {indexes};
}

function ttlPolicies(indexConfig: unknown): ExpectedTtlPolicy[] {
  const config = requireRecord(indexConfig);
  return arrayValue(config.fieldOverrides).flatMap((raw) => {
    const override = requireRecord(raw);
    const collectionGroup = stringValue(override.collectionGroup);
    const fieldPath = stringValue(override.fieldPath);
    return override.ttl === true && collectionGroup !== null &&
      fieldPath !== null ? [{collectionGroup, fieldPath}] : [];
  });
}

function normalizeTtlPolicies(value: unknown): LiveTtlPolicy[] {
  return records(value).map((record) => {
    const name = stringValue(record.name) ?? "";
    const collectionGroup = stringValue(record.collectionGroup) ??
      segmentAfter(name, "collectionGroups");
    const fieldPath = stringValue(record.fieldPath) ??
      segmentAfter(name, "fields");
    if (collectionGroup === null || fieldPath === null) {
      throw new Error("Firestore TTL policy identity is invalid.");
    }
    const ttlConfig = asRecord(record.ttlConfig);
    return Object.freeze({
      collectionGroup,
      fieldPath,
      state: normalizeEnum(stringValue(ttlConfig?.state)),
    });
  });
}

function collectBucket(projectId: string, bucketName: string): LiveBucket {
  const metadata = requireRecord(runGcloudJson([
    "storage",
    "buckets",
    "describe",
    `gs://${bucketName}`,
    `--project=${projectId}`,
  ]));
  const policy = requireRecord(runGcloudJson([
    "storage",
    "buckets",
    "get-iam-policy",
    `gs://${bucketName}`,
    `--project=${projectId}`,
  ]));
  const iamConfiguration = asRecord(metadata.iamConfiguration);
  const uniform = asRecord(iamConfiguration?.uniformBucketLevelAccess) ??
    asRecord(iamConfiguration?.bucketPolicyOnly);
  const publicMembers = arrayValue(policy.bindings).flatMap((bindingValue) => {
    const binding = requireRecord(bindingValue);
    return arrayValue(binding.members)
      .filter((member): member is string => typeof member === "string")
      .filter((member) => member === "allUsers" ||
        member === "allAuthenticatedUsers");
  });
  return Object.freeze({
    bucketName,
    location: stringValue(metadata.location),
    uniformBucketLevelAccess: booleanValue(
      metadata.uniform_bucket_level_access,
    ) ?? booleanValue(uniform?.enabled),
    publicAccessPrevention: stringValue(
      metadata.public_access_prevention,
    )?.toLowerCase() ?? stringValue(
      iamConfiguration?.publicAccessPrevention,
    )?.toLowerCase() ?? null,
    publicMembers: Object.freeze([...new Set(publicMembers)].sort()),
  });
}

function normalizeFunctions(value: unknown): LiveFunctionDeployment[] {
  return records(value).map((record) => {
    const name = stringValue(record.name);
    if (name === null) throw new Error("Cloud Function name is missing.");
    const segments = name.split("/");
    const locationIndex = segments.indexOf("locations");
    const serviceConfig = asRecord(record.serviceConfig);
    return Object.freeze({
      functionId: segments.at(-1) ?? name,
      region: stringValue(record.region) ??
        (locationIndex >= 0 ? segments[locationIndex + 1] : null) ?? "",
      state: normalizeEnum(stringValue(record.state)),
      serviceAccountEmail: stringValue(serviceConfig?.serviceAccountEmail),
    });
  });
}

function expectedFunctions(): ExpectedFunctionDeployment[] {
  const deployments = new Map<string, ExpectedFunctionDeployment>();
  for (const [functionId, value] of Object.entries(productionFunctions)) {
    const endpoint = (value as {__endpoint?: EndpointShape}).__endpoint;
    if (endpoint === undefined) continue;
    const regions = typeof endpoint.region === "string" ?
      [endpoint.region] : endpoint.region ?? [];
    if (regions.length === 0) {
      throw new Error(`Function ${functionId} has no explicit region.`);
    }
    for (const region of regions) {
      deployments.set(`${functionId}@${region}`, {functionId, region});
    }
  }
  return [...deployments.values()].sort((left, right) =>
    `${left.functionId}@${left.region}`.localeCompare(
      `${right.functionId}@${right.region}`,
    ));
}

async function collectRules(
  expected: ProductionPreflightExpectation,
): Promise<Readonly<{
  firestore: Record<string, string>;
  storage: Record<string, string>;
}>> {
  const tokenResult = spawnSync("gcloud", ["auth", "print-access-token"], {
    encoding: "utf8",
  });
  if (tokenResult.status !== 0) {
    throw new Error(
      `Could not obtain gcloud access token: ${tokenResult.stderr}`,
    );
  }
  const token = tokenResult.stdout.trim();
  const releases = await listRulesReleases(expected.projectId, token);
  const sourceCache = new Map<string, string>();
  const sourceForRelease = async (releaseId: string): Promise<string> => {
    const release = releases.find((candidate) =>
      candidate.name.endsWith(`/releases/${releaseId}`));
    if (release === undefined || typeof release.rulesetName !== "string") {
      throw new Error(`Firebase Rules release ${releaseId} is missing.`);
    }
    const cached = sourceCache.get(release.rulesetName);
    if (cached !== undefined) return cached;
    const ruleset = requireRecord(await firebaseRulesRequest(
      release.rulesetName,
      token,
      expected.projectId,
    ));
    const source = requireRecord(ruleset.source);
    const files = arrayValue(source.files).map(requireRecord);
    if (files.length !== 1 || typeof files[0].content !== "string") {
      throw new Error(`Ruleset ${release.rulesetName} must have one file.`);
    }
    sourceCache.set(release.rulesetName, files[0].content);
    return files[0].content;
  };

  const firestore: Record<string, string> = {};
  const storage: Record<string, string> = {};
  for (const world of expected.worlds) {
    const firestoreRelease = world.databaseId === "(default)" ?
      "cloud.firestore" : `cloud.firestore/${world.databaseId}`;
    firestore[world.databaseId] = await sourceForRelease(firestoreRelease);
    const exactStorageRelease = `firebase.storage/${world.bucketName}`;
    const hasExactStorageRelease = releases.some((release) =>
      release.name.endsWith(`/releases/${exactStorageRelease}`));
    const storageRelease = hasExactStorageRelease ? exactStorageRelease :
      world.worldId === "asia" ? "firebase.storage" : exactStorageRelease;
    storage[world.bucketName] = await sourceForRelease(storageRelease);
  }
  return Object.freeze({firestore, storage});
}

async function listRulesReleases(
  projectId: string,
  token: string,
): Promise<RulesRelease[]> {
  const releases: RulesRelease[] = [];
  let pageToken: string | null = null;
  do {
    const query = new URLSearchParams({pageSize: "100"});
    if (pageToken !== null) query.set("pageToken", pageToken);
    const value = requireRecord(await firebaseRulesRequest(
      `projects/${projectId}/releases?${query.toString()}`,
      token,
      projectId,
    ));
    releases.push(...arrayValue(value.releases)
      .map((release) => requireRecord(release) as unknown as RulesRelease));
    pageToken = stringValue(value.nextPageToken);
  } while (pageToken !== null && pageToken.length > 0);
  return releases;
}

async function firebaseRulesRequest(
  resource: string,
  token: string,
  quotaProjectId: string,
): Promise<unknown> {
  const response = await fetch(
    `https://firebaserules.googleapis.com/v1/${resource}`,
    {
      headers: {
        "Authorization": `Bearer ${token}`,
        "x-goog-user-project": quotaProjectId,
      },
    },
  );
  if (!response.ok) {
    throw new Error(
      `Firebase Rules API ${resource} failed with HTTP ${response.status}.`,
    );
  }
  return await response.json() as unknown;
}

function collectPermissions(
  projectId: string,
  functions: readonly LiveFunctionDeployment[],
  bucketNames: readonly string[],
): LivePermissionCheck[] {
  const serviceAccounts = [...new Set(functions
    .map((deployment) => deployment.serviceAccountEmail)
    .filter((email): email is string => email !== null))];
  const checks: LivePermissionCheck[] = [];
  for (const principalEmail of serviceAccounts) {
    const projectResource =
      `//cloudresourcemanager.googleapis.com/projects/${projectId}`;
    for (const permission of [
      "datastore.entities.get",
      "datastore.entities.list",
      "datastore.entities.create",
      "datastore.entities.update",
      "datastore.entities.delete",
    ]) {
      checks.push(troubleshootPermission(
        projectId,
        principalEmail,
        projectResource,
        permission,
      ));
    }
    for (const bucketName of bucketNames) {
      const bucketResource =
        `//storage.googleapis.com/projects/_/buckets/${bucketName}`;
      for (const permission of [
        "storage.objects.get",
        "storage.objects.create",
        "storage.objects.delete",
      ]) {
        checks.push(troubleshootPermission(
          projectId,
          principalEmail,
          bucketResource,
          permission,
        ));
      }
    }
    checks.push(troubleshootPermission(
      projectId,
      principalEmail,
      `//iam.googleapis.com/projects/${projectId}/serviceAccounts/` +
        principalEmail,
      "iam.serviceAccounts.signBlob",
    ));
  }
  return checks;
}

function troubleshootPermission(
  projectId: string,
  principalEmail: string,
  resource: string,
  permission: string,
): LivePermissionCheck {
  try {
    const result = runGcloudJson([
      "policy-troubleshoot",
      "iam",
      resource,
      `--principal-email=${principalEmail}`,
      `--permission=${permission}`,
      `--project=${projectId}`,
    ]);
    const access = findAccessValues(result);
    return Object.freeze({
      principalEmail,
      permission,
      resource,
      granted: access.includes("GRANTED") ? true :
        access.some((value) => value.includes("DENIED") ||
          value.includes("NOT_GRANTED")) ? false : null,
    });
  } catch {
    return Object.freeze({
      principalEmail,
      permission,
      resource,
      granted: null,
    });
  }
}

function findAccessValues(value: unknown): string[] {
  if (Array.isArray(value)) return value.flatMap(findAccessValues);
  const record = asRecord(value);
  if (record === null) return [];
  return Object.entries(record).flatMap(([key, child]) =>
    key === "access" && typeof child === "string" ?
      [child.toUpperCase()] : findAccessValues(child));
}

function segmentAfter(path: string, marker: string): string | null {
  const segments = path.split("/");
  const index = segments.indexOf(marker);
  return index >= 0 ? segments[index + 1] ?? null : null;
}

function normalizeEnum(value: string | null): string | null {
  return value?.toUpperCase() ?? null;
}

function arrayValue(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null &&
    !Array.isArray(value) ? value as Record<string, unknown> : null;
}

function requireRecord(value: unknown): Record<string, unknown> {
  const record = asRecord(value);
  if (record === null) throw new Error("Expected a JSON object.");
  return record;
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function booleanValue(value: unknown): boolean | null {
  return typeof value === "boolean" ? value : null;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function compareStableJson(left: unknown, right: unknown): number {
  return stableJson(left).localeCompare(stableJson(right));
}

function printReport(report: ProductionPreflightReport): void {
  for (const check of report.checks) {
    const marker = check.status === "pass" ? "PASS" :
      check.status === "warning" ? "WARN" : "FAIL";
    console.log(`[${marker}] ${check.id}: ${check.summary}`);
  }
  console.log("");
  console.log(
    `Preflight ${report.passed ? "passed" : "failed"}: ` +
    `${report.failures} failure(s), ${report.warnings} warning(s).`,
  );
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const expected = await buildExpectation(args.projectId);
  const snapshot = await collectSnapshot(expected, args.skipIam);
  const report = evaluateProductionPreflight(expected, snapshot);
  printReport(report);
  if (args.reportPath !== null) {
    await writeFile(
      args.reportPath,
      `${JSON.stringify(report, null, 2)}\n`,
      {flag: "wx"},
    );
    console.log(`Wrote report: ${args.reportPath}`);
  }
  if (!report.passed) process.exitCode = 1;
}

main()
  .catch((error: unknown) => {
    console.error(errorMessage(error));
    process.exitCode = 1;
  })
  .finally(async () => {
    await Promise.all(getApps().map(deleteApp));
  });
