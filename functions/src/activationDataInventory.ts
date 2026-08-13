/* eslint-disable require-jsdoc, valid-jsdoc */

export interface WorldActivationDataCounts {
  readonly worldId: string;
  readonly userHomes: number;
  readonly privateUsers: number;
  readonly publicProfiles: number;
  readonly userEntitlements: number;
  readonly userUsage: number;
  readonly accountSafety: number;
  readonly socialEdges: number;
  readonly blockedUsers: number;
  readonly places: number;
  readonly pendingGlobalOperations: number;
  readonly failedGlobalOperations: number;
}

export interface ActivationDataCheck {
  readonly code: string;
  readonly pass: boolean;
  readonly expected: number;
  readonly actual: number;
}

export interface ActivationDataInventoryResult {
  readonly pass: boolean;
  readonly checks: readonly ActivationDataCheck[];
}

export interface ActivationDataInventoryPolicy {
  readonly contentAccessWorldIds: ReadonlySet<string>;
  readonly homeAssignmentWorldIds: ReadonlySet<string>;
}

type CountField = Exclude<keyof WorldActivationDataCounts, "worldId">;

const GLOBAL_ACCOUNT_FIELDS: readonly CountField[] = [
  "userHomes",
  "publicProfiles",
  "userEntitlements",
  "accountSafety",
];

/** Evaluates count-level data readiness for world activation. */
export function evaluateWorldActivationDataReadiness(
  worlds: readonly WorldActivationDataCounts[],
  policy: ActivationDataInventoryPolicy,
): ActivationDataInventoryResult {
  const byWorld = new Map(worlds.map((world) => [world.worldId, world]));
  if (byWorld.size !== worlds.length) {
    throw new Error("Activation inventory contains a duplicate world.");
  }
  const asia = byWorld.get("asia");
  if (asia === undefined) {
    throw new Error("Activation inventory is missing Asia.");
  }
  const checks: ActivationDataCheck[] = [];
  for (const field of [
    "privateUsers",
    "publicProfiles",
    "userEntitlements",
    "userUsage",
    "accountSafety",
  ] as const) {
    checks.push(check(
      `asia.${field}.matchesUserHomes`,
      asia.userHomes,
      asia[field],
    ));
  }
  for (const world of worlds) {
    checks.push(check(
      `${world.worldId}.pendingGlobalOperations.empty`,
      0,
      world.pendingGlobalOperations,
    ));
    checks.push(check(
      `${world.worldId}.failedGlobalOperations.empty`,
      0,
      world.failedGlobalOperations,
    ));
    if (world.worldId === "asia") continue;
    for (const field of GLOBAL_ACCOUNT_FIELDS) {
      checks.push(check(
        `${world.worldId}.${field}.matchesAsia`,
        asia[field],
        world[field],
      ));
    }
    checks.push(check(
      `${world.worldId}.socialEdges.matchesAsia`,
      asia.socialEdges,
      world.socialEdges,
    ));
    checks.push(check(
      `${world.worldId}.blockedUsers.matchesAsia`,
      asia.blockedUsers,
      world.blockedUsers,
    ));
    if (!policy.homeAssignmentWorldIds.has(world.worldId)) {
      checks.push(check(
        `${world.worldId}.privateUsers.empty`,
        0,
        world.privateUsers,
      ));
    }
    if (!policy.contentAccessWorldIds.has(world.worldId)) {
      checks.push(check(
        `${world.worldId}.userUsage.empty`,
        0,
        world.userUsage,
      ));
      checks.push(check(
        `${world.worldId}.places.emptyBeforeContentAccess`,
        0,
        world.places,
      ));
    }
  }
  return Object.freeze({
    pass: checks.every((item) => item.pass),
    checks: Object.freeze(checks),
  });
}

function check(
  code: string,
  expected: number,
  actual: number,
): ActivationDataCheck {
  requireCount(expected);
  requireCount(actual);
  return Object.freeze({code, pass: expected === actual, expected, actual});
}

function requireCount(value: number): void {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error("Activation inventory count is invalid.");
  }
}
