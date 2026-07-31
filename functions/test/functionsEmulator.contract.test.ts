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

const RUN_EMULATOR_TESTS =
  process.env.RUN_FUNCTIONS_EMULATOR_TESTS === "1";
const PROJECT_ID = "demo-world-notes-functions";
const FUNCTIONS_ORIGIN =
  `http://127.0.0.1:5001/${PROJECT_ID}/asia-northeast1`;

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

    test("rejects invalid callable data before writing", async () => {
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
