/* eslint-disable require-jsdoc, valid-jsdoc */

import assert from "node:assert/strict";
import {randomUUID} from "node:crypto";
import {after, afterEach, before, describe, test} from "node:test";

import {
  App as AdminApp,
  deleteApp as deleteAdminApp,
  initializeApp as initializeAdminApp,
} from "firebase-admin/app";
import {
  DocumentReference,
  Firestore,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import {
  deleteApp as deleteClientApp,
  FirebaseApp,
  initializeApp as initializeClientApp,
} from "firebase/app";
import {
  Auth,
  connectAuthEmulator,
  deleteUser,
  getAuth,
  signInAnonymously,
} from "firebase/auth";

import {WORLD_CATALOG} from "../src/platform/worldCatalog";

const RUN_EMULATOR_TESTS =
  process.env.RUN_FUNCTIONS_EMULATOR_TESTS === "1";
const PROJECT_ID = "demo-world-notes-functions";
const FUNCTIONS_ORIGIN =
  `http://127.0.0.1:5001/${PROJECT_ID}/asia-northeast1`;
const TEST_LANGUAGE_OPERATION_ID =
  "00000000-0000-700a-800b-000000000001";
const TEST_PROFILE_OPERATION_ID =
  "00000000-0000-700a-800b-000000000002";

let clientApp: FirebaseApp | undefined;
let adminApp: AdminApp | undefined;
let auth: Auth | undefined;
let firestore: Firestore | undefined;
const cleanupReferences: DocumentReference[] = [];

interface CallableErrorBody {
  readonly error?: {
    readonly status?: string;
    readonly message?: string;
  };
}

interface CallableSuccessBody<T> {
  readonly result?: T;
  readonly data?: T;
}

describe(
  "Functions emulator contract",
  {skip: !RUN_EMULATOR_TESTS, concurrency: false},
  () => {
    before(() => {
      const runId = randomUUID();
      clientApp = initializeClientApp(
        {
          apiKey: "demo-api-key",
          projectId: PROJECT_ID,
        },
        `functions-contract-client-${runId}`,
      );
      auth = getAuth(clientApp);
      connectAuthEmulator(auth, "http://127.0.0.1:9099", {
        disableWarnings: true,
      });

      adminApp = initializeAdminApp(
        {projectId: PROJECT_ID},
        `functions-contract-admin-${runId}`,
      );
      firestore = getFirestore(adminApp);
    });

    afterEach(async () => {
      const references = cleanupReferences.splice(0);
      await Promise.allSettled(references.map((reference) =>
        reference.delete()));

      const currentUser = requireAuth().currentUser;
      if (currentUser !== null) {
        await deleteUser(currentUser);
      }
    });

    after(async () => {
      if (firestore !== undefined && adminApp !== undefined) {
        await firestore.terminate();
        await deleteAdminApp(adminApp);
      }
      if (clientApp !== undefined) {
        await deleteClientApp(clientApp);
      }
    });

    test("rejects a callable request without authentication", async () => {
      const response = await callFunction(
        "setMyNotesNotificationEnabled",
        {worldId: "asia", enabled: true},
      );
      const body = await response.json() as CallableErrorBody;

      assert.equal(response.status, 401);
      assert.equal(body.error?.status, "UNAUTHENTICATED");
    });

    test("writes an authenticated setting through the callable", async () => {
      const credential = await signInAnonymously(requireAuth());
      await seedReadyUser(credential.user.uid);
      const idToken = await credential.user.getIdToken();
      const settingReference = requireFirestore()
        .collection("users")
        .doc(credential.user.uid)
        .collection("notificationSettings")
        .doc("main");
      cleanupReferences.push(settingReference);

      const response = await callFunction(
        "setMyNotesNotificationEnabled",
        {worldId: "asia", enabled: true},
        idToken,
      );
      const body = await response.json() as CallableSuccessBody<{
        ok: boolean;
        worldId: string;
      }>;
      const setting = await settingReference.get();

      assert.equal(response.status, 200);
      assert.equal((body.result ?? body.data)?.ok, true);
      assert.equal((body.result ?? body.data)?.worldId, "asia");
      assert.equal(setting.get("myNotesEnabled"), true);
      assert.notEqual(setting.get("updatedAt"), undefined);
    });

    test("rejects a stateful callable before world bootstrap", async () => {
      const credential = await signInAnonymously(requireAuth());
      const idToken = await credential.user.getIdToken();
      const settingReference = requireFirestore()
        .collection("users")
        .doc(credential.user.uid)
        .collection("notificationSettings")
        .doc("main");
      cleanupReferences.push(settingReference);

      const response = await callFunction(
        "setMyNotesNotificationEnabled",
        {worldId: "asia", enabled: true},
        idToken,
      );
      const body = await response.json() as CallableErrorBody;

      assert.equal(response.status, 400);
      assert.equal(body.error?.status, "FAILED_PRECONDITION");
      assert.equal((await settingReference.get()).exists, false);
    });

    test("rejects invalid callable data before writing", async () => {
      const credential = await signInAnonymously(requireAuth());
      await seedReadyUser(credential.user.uid);
      const idToken = await credential.user.getIdToken();
      const settingReference = requireFirestore()
        .collection("users")
        .doc(credential.user.uid)
        .collection("notificationSettings")
        .doc("main");
      cleanupReferences.push(settingReference);

      const response = await callFunction(
        "setMyNotesNotificationEnabled",
        {worldId: "asia", enabled: "yes"},
        idToken,
      );
      const body = await response.json() as CallableErrorBody;
      const setting = await settingReference.get();

      assert.equal(response.status, 400);
      assert.equal(body.error?.status, "INVALID_ARGUMENT");
      assert.equal(setting.exists, false);
    });

    test("rejects a callable request without an explicit world", async () => {
      const credential = await signInAnonymously(requireAuth());
      const idToken = await credential.user.getIdToken();

      const response = await callFunction(
        "setMyNotesNotificationEnabled",
        {enabled: true},
        idToken,
      );
      const body = await response.json() as CallableErrorBody;

      assert.equal(response.status, 400);
      assert.equal(body.error?.status, "INVALID_ARGUMENT");
    });

    test("atomically bootstraps the caller's Asia account", async () => {
      const credential = await signInAnonymously(requireAuth());
      const uid = credential.user.uid;
      const idToken = await credential.user.getIdToken();
      const db = requireFirestore();
      const references = [
        db.collection("userHomes").doc(uid),
        db.collection("users").doc(uid),
        db.collection("publicProfiles").doc(uid),
        db.collection("userEntitlements").doc(uid),
        db.collection("userUsage").doc(uid),
        db.collection("accountSafety").doc(uid),
      ];
      cleanupReferences.push(...references);

      const response = await callFunction(
        "assignHomeWorld",
        {worldId: "asia", homeWorld: "asia"},
        idToken,
      );
      const body = await response.json() as CallableSuccessBody<{
        homeWorld: string;
        epoch: number;
        ready: boolean;
        assignedNow: boolean;
        worldId: string;
      }>;
      const result = body.result ?? body.data;
      const [home, user, profile, entitlement, usage, safety] =
        await Promise.all(references.map((reference) => reference.get()));

      assert.equal(response.status, 200);
      assert.equal(result?.homeWorld, "asia");
      assert.equal(result?.epoch, 1);
      assert.equal(result?.ready, true);
      assert.equal(result?.assignedNow, true);
      assert.equal(result?.worldId, "asia");
      assert.equal(home.get("world"), "asia");
      assert.equal(home.get("epoch"), 1);
      assert.equal(user.get("displayName"), "User");
      assert.equal(user.get("languagePreference"), "system");
      assert.equal(user.get("languagePreferenceRevision"), 0);
      assert.equal(profile.get("followerCount"), 0);
      assert.equal(profile.get("followingCount"), 0);
      assert.equal(profile.get("revision"), 2);
      assert.equal(entitlement.get("isPremium"), false);
      assert.equal(entitlement.get("sourceCheckedAt"), null);
      assert.equal(entitlement.get("revision"), 2);
      assert.equal(usage.get("activeNoteCount"), 0);
      assert.equal(safety.get("violationPoints"), 0);
      assert.equal(safety.get("revision"), 2);
      assert.equal(safety.get("authorityWorld"), "asia");
    });

    test("accepts a revisioned home profile update", async () => {
      const credential = await signInAnonymously(requireAuth());
      const uid = credential.user.uid;
      const idToken = await credential.user.getIdToken();
      const db = requireFirestore();
      const homeRef = db.collection("userHomes").doc(uid);
      const userRef = db.collection("users").doc(uid);
      const profileRef = db.collection("publicProfiles").doc(uid);
      const entitlementRef = db.collection("userEntitlements").doc(uid);
      const usageRef = db.collection("userUsage").doc(uid);
      const safetyRef = db.collection("accountSafety").doc(uid);
      const operationRef = db
        .collection("globalOperations")
        .doc(TEST_PROFILE_OPERATION_ID);
      cleanupReferences.push(
        homeRef,
        userRef,
        profileRef,
        entitlementRef,
        usageRef,
        safetyRef,
        operationRef,
      );
      const bootstrap = await callFunction(
        "assignHomeWorld",
        {worldId: "asia", homeWorld: "asia"},
        idToken,
      );
      assert.equal(bootstrap.status, 200);

      const response = await callFunction(
        "updateDisplayName",
        {
          worldId: "asia",
          operationId: TEST_PROFILE_OPERATION_ID,
          displayName: "Updated User",
        },
        idToken,
      );
      const body = await response.json() as CallableSuccessBody<{
        displayName: string;
        accepted: boolean;
        operationId: string;
        authorityWorld: string;
        revision: number;
        status: string;
      }>;
      const result = body.result ?? body.data;
      const [user, profile, operation] = await Promise.all([
        userRef.get(),
        profileRef.get(),
        operationRef.get(),
      ]);

      assert.equal(response.status, 200);
      assert.equal(result?.displayName, "Updated User");
      assert.equal(result?.accepted, true);
      assert.equal(result?.operationId, TEST_PROFILE_OPERATION_ID);
      assert.equal(result?.authorityWorld, "asia");
      assert.equal(result?.revision, 3);
      assert.match(result?.status ?? "", /^(pending|complete)$/);
      assert.equal(user.get("displayName"), "Updated User");
      assert.equal(profile.get("displayName"), "Updated User");
      assert.equal(profile.get("revision"), 3);
      assert.equal(operation.get("operationType"), "updatePublicProfile");
      assert.deepEqual(
        operation.get("requiredWorlds"),
        ["asia", "northAmerica", "europe"],
      );
    });

    test("makes a repeated home assignment idempotent", async () => {
      const credential = await signInAnonymously(requireAuth());
      const uid = credential.user.uid;
      const idToken = await credential.user.getIdToken();
      const db = requireFirestore();
      cleanupReferences.push(
        db.collection("userHomes").doc(uid),
        db.collection("users").doc(uid),
        db.collection("publicProfiles").doc(uid),
        db.collection("userEntitlements").doc(uid),
        db.collection("userUsage").doc(uid),
        db.collection("accountSafety").doc(uid),
      );

      const responses = await Promise.all([
        callFunction(
          "assignHomeWorld",
          {worldId: "asia", homeWorld: "asia"},
          idToken,
        ),
        callFunction(
          "assignHomeWorld",
          {worldId: "asia", homeWorld: "asia"},
          idToken,
        ),
      ]);
      const bodies = await Promise.all(responses.map(async (response) =>
        await response.json() as CallableSuccessBody<{
          assignedNow: boolean;
        }>));

      assert.deepEqual(
        responses.map((response) => response.status),
        [200, 200],
      );
      assert.deepEqual(
        bodies
          .map((body) => (body.result ?? body.data)?.assignedNow)
          .sort(),
        [false, true],
      );
    });

    test(
      "keeps aggregate message-like state and count consistent",
      async () => {
        const credential = await signInAnonymously(requireAuth());
        const uid = credential.user.uid;
        const idToken = await credential.user.getIdToken();
        const db = requireFirestore();
        const placeRef = db.collection("places").doc(`like-${randomUUID()}`);
        const messageRef = placeRef.collection("messages").doc("message-1");
        const stateRef = placeRef.collection("likedMessages").doc(uid);
        cleanupReferences.push(
          db.collection("userHomes").doc(uid),
          db.collection("users").doc(uid),
          db.collection("publicProfiles").doc(uid),
          db.collection("userEntitlements").doc(uid),
          db.collection("userUsage").doc(uid),
          db.collection("accountSafety").doc(uid),
          stateRef,
          messageRef,
          placeRef,
        );
        const bootstrap = await callFunction(
          "assignHomeWorld",
          {worldId: "asia", homeWorld: "asia"},
          idToken,
        );
        assert.equal(bootstrap.status, 200);
        const now = Date.now();
        await placeRef.set({
          createdByUserId: "creator",
          visibility: "public",
          isArchived: false,
          isModerationHidden: false,
          publishAt: Timestamp.fromMillis(now - 60_000),
          expiresAt: Timestamp.fromMillis(now + 60_000),
        });
        await messageRef.set({
          userId: "author",
          isVisible: true,
          isPubliclyVisible: true,
          isDeleted: false,
          likeCount: 0,
        });

        for (const liked of [true, true, false]) {
          const response = await callFunction(
            "setMessageLike",
            {
              worldId: "asia",
              placeId: placeRef.id,
              messageId: messageRef.id,
              liked,
            },
            idToken,
          );
          assert.equal(response.status, 200);
        }

        const [state, message] = await Promise.all([
          stateRef.get(),
          messageRef.get(),
        ]);
        assert.deepEqual(state.get("messageIds"), []);
        assert.equal(state.get("userId"), uid);
        assert.equal(state.get("placeId"), placeRef.id);
        assert.equal(message.get("likeCount"), 0);
      },
    );

    test(
      "authorizes a private-note delegate through its administrator record",
      async () => {
        const credential = await signInAnonymously(requireAuth());
        const uid = credential.user.uid;
        const idToken = await credential.user.getIdToken();
        const db = requireFirestore();
        const placeRef = db
          .collection("places")
          .doc(`delegate-${randomUUID()}`);
        const administratorRef = placeRef.collection("administrators").doc(uid);
        const messageRef = placeRef.collection("messages").doc("message-1");
        const stateRef = placeRef.collection("likedMessages").doc(uid);
        cleanupReferences.push(
          db.collection("userHomes").doc(uid),
          db.collection("users").doc(uid),
          db.collection("publicProfiles").doc(uid),
          db.collection("userEntitlements").doc(uid),
          db.collection("userUsage").doc(uid),
          db.collection("accountSafety").doc(uid),
          stateRef,
          messageRef,
          administratorRef,
          placeRef,
        );
        const bootstrap = await callFunction(
          "assignHomeWorld",
          {worldId: "asia", homeWorld: "asia"},
          idToken,
        );
        assert.equal(bootstrap.status, 200);
        const now = Date.now();
        await Promise.all([
          placeRef.set({
            createdByUserId: "creator",
            visibility: "private",
            passwordVersion: 1,
            isArchived: false,
            isModerationHidden: false,
            publishAt: Timestamp.fromMillis(now - 60_000),
            expiresAt: Timestamp.fromMillis(now + 60_000),
          }),
          administratorRef.set({
            userId: uid,
            invitedByUid: "creator",
            inviteId: "test-invite",
            grantedAt: Timestamp.now(),
          }),
          messageRef.set({
            userId: "author",
            isVisible: true,
            isPubliclyVisible: true,
            isDeleted: false,
            likeCount: 0,
          }),
        ]);

        const response = await callFunction(
          "setMessageLike",
          {
            worldId: "asia",
            placeId: placeRef.id,
            messageId: messageRef.id,
            liked: true,
          },
          idToken,
        );

        assert.equal(response.status, 200);
        assert.deepEqual((await stateRef.get()).get("messageIds"), [
          messageRef.id,
        ]);
      },
    );

    test("commits and replays a language preference operation", async () => {
      const credential = await signInAnonymously(requireAuth());
      const uid = credential.user.uid;
      const idToken = await credential.user.getIdToken();
      const operationId = TEST_LANGUAGE_OPERATION_ID;
      const db = requireFirestore();
      const userReference = db.collection("users").doc(uid);
      const operationReference = db
        .collection("globalOperations")
        .doc(operationId);
      cleanupReferences.push(
        db.collection("userHomes").doc(uid),
        userReference,
        db.collection("publicProfiles").doc(uid),
        db.collection("userEntitlements").doc(uid),
        db.collection("userUsage").doc(uid),
        db.collection("accountSafety").doc(uid),
        operationReference,
      );
      const bootstrap = await callFunction(
        "assignHomeWorld",
        {worldId: "asia", homeWorld: "asia"},
        idToken,
      );
      assert.equal(bootstrap.status, 200);

      const responses = await Promise.all([
        callFunction(
          "setLanguagePreference",
          {worldId: "asia", operationId, languagePreference: "ja"},
          idToken,
        ),
        callFunction(
          "setLanguagePreference",
          {worldId: "asia", operationId, languagePreference: "ja"},
          idToken,
        ),
      ]);
      const bodies = await Promise.all(responses.map(async (response) =>
        await response.json() as CallableSuccessBody<{
        accepted: boolean;
        replayed: boolean;
        operationId: string;
        authorityWorld: string;
        revision: number;
        status: string;
        }>));
      const results = bodies.map((body) => body.result ?? body.data);
      const acceptedResult = results.find((result) => !result?.replayed);
      const [user, operation] = await Promise.all([
        userReference.get(),
        operationReference.get(),
      ]);

      assert.deepEqual(
        responses.map((response) => response.status),
        [200, 200],
      );
      assert.deepEqual(
        results.map((result) => result?.replayed).sort(),
        [false, true],
      );
      assert.equal(acceptedResult?.accepted, true);
      assert.equal(acceptedResult?.operationId, operationId);
      assert.equal(acceptedResult?.authorityWorld, "asia");
      assert.equal(acceptedResult?.revision, 1);
      assert.equal(acceptedResult?.status, "complete");
      assert.equal(user.get("languagePreference"), "ja");
      assert.equal(user.get("languagePreferenceRevision"), 1);
      assert.equal(operation.get("ownerUid"), uid);
      assert.equal(operation.get("operationType"), "setLanguagePreference");
      assert.equal(operation.get("entityId"), uid);
      assert.equal(operation.get("status"), "complete");
      assert.deepEqual(operation.get("requiredWorlds"), ["asia"]);
      assert.equal(operation.get("worldAcks.asia.revision"), 1);
      assert.equal(
        operation.get("worldCatalogVersion"),
        WORLD_CATALOG.catalogVersion,
      );
      assert.match(operation.get("payloadHash") as string, /^[0-9a-f]{64}$/);
      assert.notEqual(operation.get("completedAt"), undefined);
      assert.notEqual(operation.get("expireAt"), undefined);

      const conflict = await callFunction(
        "setLanguagePreference",
        {worldId: "asia", operationId, languagePreference: "en"},
        idToken,
      );
      const conflictBody = await conflict.json() as CallableErrorBody;
      assert.equal(conflict.status, 409);
      assert.equal(conflictBody.error?.status, "ALREADY_EXISTS");
      assert.equal(
        (await userReference.get()).get("languagePreference"),
        "ja",
      );
      assert.equal(
        (await userReference.get()).get("languagePreferenceRevision"),
        1,
      );
    });

    test("rejects a home world that is not assignment-enabled", async () => {
      const credential = await signInAnonymously(requireAuth());
      const idToken = await credential.user.getIdToken();

      const response = await callFunction(
        "assignHomeWorld",
        {worldId: "asia", homeWorld: "europe"},
        idToken,
      );
      const body = await response.json() as CallableErrorBody;

      assert.equal(response.status, 400);
      assert.equal(body.error?.status, "FAILED_PRECONDITION");
    });
  },
);

function requireAuth(): Auth {
  if (auth === undefined) {
    throw new Error("Auth emulator client is not initialized.");
  }
  return auth;
}

function requireFirestore(): Firestore {
  if (firestore === undefined) {
    throw new Error("Firestore emulator client is not initialized.");
  }
  return firestore;
}

async function seedReadyUser(uid: string): Promise<void> {
  const reference = requireFirestore().collection("userHomes").doc(uid);
  cleanupReferences.push(reference);
  await reference.set({
    world: "asia",
    epoch: 1,
    createdAt: new Date(),
  });
}

async function callFunction(
  functionName: string,
  data: unknown,
  idToken?: string,
): Promise<Response> {
  const headers: Record<string, string> = {
    "content-type": "application/json",
  };
  if (idToken !== undefined) {
    headers.authorization = `Bearer ${idToken}`;
    headers["x-firebase-appcheck"] = idToken;
  }

  return fetch(`${FUNCTIONS_ORIGIN}/${functionName}`, {
    method: "POST",
    headers,
    body: JSON.stringify({data}),
  });
}
