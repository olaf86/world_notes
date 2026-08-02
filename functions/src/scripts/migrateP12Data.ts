/* eslint-disable require-jsdoc, no-console */

import {deleteApp, initializeApp} from "firebase-admin/app";
import {getAuth, UserRecord} from "firebase-admin/auth";
import {
  DocumentReference,
  DocumentSnapshot,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";

import {
  newGlobalOperationId,
  requireOperationId,
} from "../globalOperations";
import {
  createAdminWorldFirestoreClient,
  DEFAULT_FIRESTORE_DATABASE_ID,
} from "../platform/worldFirestoreProvider";
import {
  executeEntitlementUpdate,
  executePublicProfilePublish,
} from "../profileEntitlementReplication";

const PROJECT_ID = "world-notes-prod";
const HOME_WORLD = "asia";
const HOME_EPOCH = 1;
const WRITE_BATCH_SIZE = 400;
const PROFILE_OPERATION_FIELD = "profileReplicationOperationId";
const ENTITLEMENT_OPERATION_FIELD = "entitlementReplicationOperationId";
const LANGUAGES = new Set([
  "system",
  "en",
  "ja",
  "ko",
  "zh-Hans",
  "zh-Hant",
]);

interface MigrationArgs {
  readonly apply: boolean;
  readonly confirmProject?: string;
}

interface AccountPlan {
  readonly uid: string;
  readonly authUser: UserRecord;
  readonly home: Record<string, unknown>;
  readonly user: Record<string, unknown>;
  readonly profile: Record<string, unknown>;
  readonly entitlement: Record<string, unknown>;
  readonly usage: Record<string, unknown>;
}

interface SnapshotPlan {
  readonly reference: DocumentReference;
  readonly data: Record<string, unknown>;
}

function parseArgs(argv: readonly string[]): MigrationArgs {
  let apply = false;
  let confirmProject: string | undefined;
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--apply") {
      apply = true;
    } else if (arg === "--confirm-project") {
      confirmProject = argv[index + 1];
      index += 1;
    } else {
      throw new Error(`Unsupported argument: ${arg}.`);
    }
  }
  if (apply && confirmProject !== PROJECT_ID) {
    throw new Error(
      `Applying requires --confirm-project ${PROJECT_ID}.`,
    );
  }
  return {apply, confirmProject};
}

async function listAuthUsers(): Promise<Map<string, UserRecord>> {
  const users = new Map<string, UserRecord>();
  let pageToken: string | undefined;
  do {
    const page = await getAuth().listUsers(1_000, pageToken);
    for (const user of page.users) users.set(user.uid, user);
    pageToken = page.pageToken;
  } while (pageToken !== undefined);
  return users;
}

async function collectionMap(
  firestore: Firestore,
  collection: string,
): Promise<Map<string, DocumentSnapshot>> {
  const snapshot = await firestore.collection(collection).get();
  return new Map(snapshot.docs.map((document) => [document.id, document]));
}

async function buildPlans(
  firestore: Firestore,
): Promise<{
  accounts: AccountPlan[];
  snapshots: SnapshotPlan[];
}> {
  // Read sequentially so a credential/query failure cannot leave other RPCs
  // active when main closes the Admin client and reports the original error.
  const authUsers = await listAuthUsers();
  const homes = await collectionMap(firestore, "userHomes");
  const users = await collectionMap(firestore, "users");
  const profiles = await collectionMap(firestore, "publicProfiles");
  const entitlements = await collectionMap(firestore, "userEntitlements");
  const usages = await collectionMap(firestore, "userUsage");
  const places = await firestore.collection("places").get();
  const members = await firestore.collectionGroup("members").get();
  const accountIds = new Set([
    ...authUsers.keys(),
    ...homes.keys(),
    ...users.keys(),
    ...profiles.keys(),
    ...entitlements.keys(),
    ...usages.keys(),
  ]);
  const activeNoteCounts = new Map<string, number>();
  for (const place of places.docs) {
    const uid = requireUid(place.get("createdByUserId"), "place creator");
    if (place.get("isArchived") !== true) {
      activeNoteCounts.set(uid, (activeNoteCounts.get(uid) ?? 0) + 1);
    }
  }

  const now = Timestamp.now();
  const accounts: AccountPlan[] = [];
  const profileByUid = new Map<string, Record<string, unknown>>();
  for (const uid of [...accountIds].sort()) {
    const authUser = authUsers.get(uid);
    if (authUser === undefined) {
      throw new Error("Firestore account has no Firebase Auth user.");
    }
    const home = homes.get(uid);
    if (home?.exists &&
        (home.get("world") !== HOME_WORLD ||
         home.get("epoch") !== HOME_EPOCH)) {
      throw new Error("Existing home assignment is incompatible.");
    }
    const user = users.get(uid);
    const profile = profiles.get(uid);
    const entitlement = entitlements.get(uid);
    const createdAt = firstTimestamp([
      home?.get("createdAt"),
      user?.get("createdAt"),
      profile?.get("createdAt"),
      Timestamp.fromDate(new Date(authUser.metadata.creationTime)),
    ]);
    const displayName = boundedDisplayName(
      authUser.displayName ?? user?.get("displayName"),
    );
    const photoUrl = nullableString(
      authUser.photoURL ?? profile?.get("photoUrl") ?? null,
    );
    const profileRevision = positiveInteger(profile?.get("revision"), 1);
    const profileData = {
      displayName,
      photoUrl,
      photoVersion: positiveInteger(profile?.get("photoVersion"), 1),
      revision: profileRevision,
      followerCount: nonNegativeInteger(profile?.get("followerCount"), 0),
      followingCount: nonNegativeInteger(profile?.get("followingCount"), 0),
      createdAt,
      updatedAt: timestamp(profile?.get("updatedAt"), now),
    };
    profileByUid.set(uid, profileData);
    const isPremium = boolean(
      entitlement?.get("isPremium"),
      user?.get("isPremium") === true,
    );
    accounts.push({
      uid,
      authUser,
      home: {
        world: HOME_WORLD,
        epoch: HOME_EPOCH,
        [PROFILE_OPERATION_FIELD]: operationId(
          home?.get(PROFILE_OPERATION_FIELD),
        ),
        [ENTITLEMENT_OPERATION_FIELD]: operationId(
          home?.get(ENTITLEMENT_OPERATION_FIELD),
        ),
        createdAt,
      },
      user: {
        displayName,
        email: nullableString(authUser.email ?? null),
        photoUrl,
        languagePreference: language(user?.get("languagePreference")),
        languagePreferenceRevision: nonNegativeInteger(
          user?.get("languagePreferenceRevision"),
          0,
        ),
        createdAt,
        updatedAt: timestamp(user?.get("updatedAt"), now),
        ...preservedPrivateAccountFields(user),
      },
      profile: profileData,
      entitlement: {
        isPremium,
        revision: positiveInteger(entitlement?.get("revision"), 1),
        sourceCheckedAt: nullableTimestamp(
          entitlement?.get("sourceCheckedAt"),
        ),
        updatedAt: timestamp(entitlement?.get("updatedAt"), now),
      },
      usage: {
        activeNoteCount: activeNoteCounts.get(uid) ?? 0,
        updatedAt: timestamp(usages.get(uid)?.get("updatedAt"), now),
      },
    });
  }

  const snapshots: SnapshotPlan[] = [];
  for (const place of places.docs) {
    const uid = requireUid(place.get("createdByUserId"), "place creator");
    const profile = profileByUid.get(uid);
    if (profile === undefined) {
      throw new Error("Place creator profile missing.");
    }
    snapshots.push({
      reference: place.ref,
      data: {
        creatorName: profile.displayName,
        creatorPhotoUrl: profile.photoUrl,
        creatorPhotoVersion: profile.photoVersion,
        creatorProfileRevision: profile.revision,
      },
    });
  }
  for (const member of members.docs) {
    const uid = requireUid(member.get("userId"), "member user");
    const profile = profileByUid.get(uid);
    if (profile === undefined) throw new Error("Member profile missing.");
    snapshots.push({
      reference: member.ref,
      data: {
        displayName: profile.displayName,
        profileRevision: profile.revision,
      },
    });
  }
  return {accounts, snapshots};
}

async function writeAccounts(
  firestore: Firestore,
  accounts: readonly AccountPlan[],
): Promise<void> {
  for (const account of accounts) {
    await firestore.runTransaction(async (transaction) => {
      transaction.set(
        firestore.collection("userHomes").doc(account.uid),
        account.home,
      );
      transaction.set(
        firestore.collection("users").doc(account.uid),
        account.user,
      );
      transaction.set(
        firestore.collection("publicProfiles").doc(account.uid),
        account.profile,
      );
      transaction.set(
        firestore.collection("userEntitlements").doc(account.uid),
        account.entitlement,
      );
      transaction.set(
        firestore.collection("userUsage").doc(account.uid),
        account.usage,
      );
    });
  }
}

async function publishAccounts(
  firestore: Firestore,
  accounts: readonly AccountPlan[],
): Promise<void> {
  for (const account of accounts) {
    await executePublicProfilePublish({
      firestore,
      authorityWorld: HOME_WORLD,
      uid: account.uid,
      operationId: account.home[PROFILE_OPERATION_FIELD],
      sourceEventId: "p12DevelopmentMigration:profile",
    });
    await executeEntitlementUpdate({
      firestore,
      authorityWorld: HOME_WORLD,
      uid: account.uid,
      operationId: account.home[ENTITLEMENT_OPERATION_FIELD],
      isPremium: account.entitlement.isPremium === true,
      sourceCheckedAt: account.entitlement.sourceCheckedAt as Timestamp | null,
      sourceEventId: "p12DevelopmentMigration:entitlement",
    });
  }
}

async function writeSnapshots(
  firestore: Firestore,
  snapshots: readonly SnapshotPlan[],
): Promise<void> {
  for (let index = 0; index < snapshots.length; index += WRITE_BATCH_SIZE) {
    const batch = firestore.batch();
    for (const snapshot of snapshots.slice(index, index + WRITE_BATCH_SIZE)) {
      batch.update(snapshot.reference, snapshot.data);
    }
    await batch.commit();
  }
}

function operationId(value: unknown): string {
  try {
    return requireOperationId(value);
  } catch {
    return newGlobalOperationId();
  }
}

function requireUid(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0 || value.includes("/")) {
    throw new Error(`${field} is invalid.`);
  }
  return value;
}

function boundedDisplayName(value: unknown): string {
  if (typeof value !== "string" || value.trim().length === 0) return "User";
  return Array.from(value.trim()).slice(0, 20).join("");
}

function nullableString(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value !== "string") throw new Error("String field is invalid.");
  const normalized = value.trim();
  return normalized.length === 0 ? null : normalized;
}

function language(value: unknown): string {
  return typeof value === "string" && LANGUAGES.has(value) ? value : "system";
}

function positiveInteger(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0 ?
    value : fallback;
}

function nonNegativeInteger(value: unknown, fallback: number): number {
  const valid = typeof value === "number" &&
    Number.isSafeInteger(value) && value >= 0;
  return valid ? value : fallback;
}

function boolean(value: unknown, fallback: boolean): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function timestamp(value: unknown, fallback: Timestamp): Timestamp {
  return value instanceof Timestamp ? value : fallback;
}

function nullableTimestamp(value: unknown): Timestamp | null {
  return value instanceof Timestamp ? value : null;
}

function firstTimestamp(values: readonly unknown[]): Timestamp {
  const value = values.find((candidate) => candidate instanceof Timestamp);
  if (!(value instanceof Timestamp)) throw new Error("Timestamp is missing.");
  return value;
}

/**
 * Preserves current private safety/preferences while dropping old fields.
 *
 * @param {DocumentSnapshot | undefined} snapshot Existing user document.
 * @return {Record<string, unknown>} Allowlisted private fields.
 */
function preservedPrivateAccountFields(
  snapshot: DocumentSnapshot | undefined,
): Record<string, unknown> {
  if (snapshot === undefined || !snapshot.exists) return {};
  const result: Record<string, unknown> = {};
  for (const field of [
    "moderationStatus",
    "violationPoints",
    "lastViolationAt",
    "restrictedUntil",
    "bannedUntil",
    "locale",
  ]) {
    const value = snapshot.get(field);
    if (value !== undefined) result[field] = value;
  }
  return result;
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const app = initializeApp({projectId: PROJECT_ID});
  const firestore = createAdminWorldFirestoreClient(
    app,
    DEFAULT_FIRESTORE_DATABASE_ID,
  );
  try {
    const plans = await buildPlans(firestore);
    console.log(`project: ${PROJECT_ID}`);
    console.log(`mode: ${args.apply ? "apply" : "dry-run"}`);
    console.log(`accounts: ${plans.accounts.length}`);
    console.log(`profile snapshots: ${plans.snapshots.length}`);
    if (!args.apply) return;
    await writeAccounts(firestore, plans.accounts);
    await publishAccounts(firestore, plans.accounts);
    const refreshedPlans = await buildPlans(firestore);
    await writeSnapshots(firestore, refreshedPlans.snapshots);
    console.log("P12 development data migration complete.");
  } finally {
    await firestore.terminate();
    await deleteApp(app);
  }
}

void main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
