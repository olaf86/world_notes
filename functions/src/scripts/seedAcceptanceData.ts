/* eslint-disable require-jsdoc, max-len, no-console */
import {deleteApp, initializeApp} from "firebase-admin/app";
import {getAuth, UserRecord} from "firebase-admin/auth";
import {FieldValue} from "firebase-admin/firestore";

import {
  createAdminWorldFirestoreClient,
  DEFAULT_FIRESTORE_DATABASE_ID,
} from "../platform/worldFirestoreProvider";

const projectId = process.env.GCLOUD_PROJECT || "world-notes-prod";
process.env.FIREBASE_AUTH_EMULATOR_HOST =
  process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099";
process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";

const app = initializeApp({projectId});
const auth = getAuth(app);
const db = createAdminWorldFirestoreClient(
  app,
  DEFAULT_FIRESTORE_DATABASE_ID,
);

const acceptanceUser = {
  email: process.env.ACCEPTANCE_AUTH_EMAIL || "acceptance@example.com",
  password: process.env.ACCEPTANCE_AUTH_PASSWORD || "Passw0rd!",
  displayName: "Acceptance Tester",
};

function isFirebaseError(error: unknown): error is {code: string} {
  return typeof error === "object" &&
    error != null &&
    "code" in error &&
    typeof (error as {code?: unknown}).code === "string";
}

async function ensureAuthUser(): Promise<UserRecord> {
  try {
    const user = await auth.getUserByEmail(acceptanceUser.email);
    return auth.updateUser(user.uid, {
      password: acceptanceUser.password,
      displayName: acceptanceUser.displayName,
      emailVerified: true,
    });
  } catch (error) {
    if (!isFirebaseError(error) || error.code !== "auth/user-not-found") {
      throw error;
    }
    return auth.createUser({
      email: acceptanceUser.email,
      password: acceptanceUser.password,
      displayName: acceptanceUser.displayName,
      emailVerified: true,
    });
  }
}

async function seedAccount(user: UserRecord): Promise<void> {
  const now = FieldValue.serverTimestamp();
  const batch = db.batch();

  // The directory assignment and the destination marker intentionally match.
  // In the emulator the Asia world is backed by the default database.
  batch.set(db.collection("userHomes").doc(user.uid), {
    world: "asia",
    epoch: 1,
    createdAt: now,
  });
  batch.set(db.collection("users").doc(user.uid), {
    displayName: acceptanceUser.displayName,
    email: acceptanceUser.email,
    photoUrl: null,
    languagePreference: "system",
    languagePreferenceRevision: 0,
    createdAt: now,
    updatedAt: now,
  });
  batch.set(db.collection("publicProfiles").doc(user.uid), {
    displayName: acceptanceUser.displayName,
    photoUrl: null,
    photoVersion: 1,
    revision: 1,
    followerCount: 0,
    followingCount: 0,
    createdAt: now,
    updatedAt: now,
  });
  batch.set(db.collection("userEntitlements").doc(user.uid), {
    isPremium: false,
    revision: 1,
    sourceCheckedAt: null,
    updatedAt: now,
  });
  batch.set(db.collection("userUsage").doc(user.uid), {
    activeNoteCount: 0,
    updatedAt: now,
  });

  await batch.commit();
}

async function main(): Promise<void> {
  const user = await ensureAuthUser();
  await seedAccount(user);

  console.log("Acceptance seed completed.");
  console.log(`projectId: ${projectId}`);
  console.log(`uid: ${user.uid}`);
  console.log(`email: ${acceptanceUser.email}`);
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await deleteApp(app);
  });
