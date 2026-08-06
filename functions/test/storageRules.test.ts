/* eslint-disable require-jsdoc */

import {readFile} from "node:fs/promises";
import {resolve} from "node:path";
import {after, before, beforeEach, describe, test} from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import firebase from "firebase/compat/app";
import "firebase/compat/storage";

const hasStorageEmulator =
  process.env.FIREBASE_STORAGE_EMULATOR_HOST !== undefined;
const MESSAGE_ID = "00000000-0000-700a-800b-000000000001";
const MESSAGE_PATH =
  `images/messages/test-place/alice/${MESSAGE_ID}/0.webp`;
const PIN_PATH =
  "images/pins/test-place/alice/" +
  "00000000-0000-700a-800b-000000000002.webp";

let rules: RulesTestEnvironment | undefined;

describe(
  "Storage Security Rules",
  {skip: !hasStorageEmulator, concurrency: false},
  () => {
    before(async () => {
      rules = await initializeTestEnvironment({
        projectId: "demo-world-notes-storage-rules",
        storage: {
          rules: await readFile(
            resolve(process.cwd(), "../storage.rules"),
            "utf8",
          ),
        },
      });
    });

    beforeEach(async () => requireRules().clearStorage());
    after(async () => rules?.cleanup());

    test(
      "allows only owner-scoped immutable message image creation",
      async () => {
        const alice = requireRules().authenticatedContext("alice");
        const bob = requireRules().authenticatedContext("bob");
        const bytes = new Uint8Array([1, 2, 3]);

        await assertFails(
          upload(bob.storage().ref(MESSAGE_PATH), bytes, {
            contentType: "image/webp",
          }),
        );
        await assertSucceeds(
          upload(alice.storage().ref(MESSAGE_PATH), bytes, {
            contentType: "image/webp",
          }),
        );
        await assertFails(
          upload(alice.storage().ref(MESSAGE_PATH), bytes, {
            contentType: "image/webp",
          }),
        );
      },
    );

    test("denies direct reads and deletes after a valid upload", async () => {
      const alice = requireRules().authenticatedContext("alice");
      const ref = alice.storage().ref(
        MESSAGE_PATH.replace(
          MESSAGE_ID,
          "00000000-0000-700a-800b-000000000003",
        ),
      );
      await assertSucceeds(
        upload(ref, new Uint8Array([1]), {contentType: "image/webp"}),
      );

      await assertFails(ref.getDownloadURL());
      await assertFails(ref.getMetadata());
      await assertFails(ref.delete());
    });

    test("enforces content type, size, and canonical file names", async () => {
      const alice = requireRules().authenticatedContext("alice");
      await assertFails(
        upload(alice.storage().ref(MESSAGE_PATH), new Uint8Array([1]), {
          contentType: "image/png",
        }),
      );
      await assertFails(
        upload(
          alice.storage().ref(MESSAGE_PATH),
          new Uint8Array(2 * 1024 * 1024 + 1),
          {contentType: "image/webp"},
        ),
      );
      await assertFails(
        upload(
          alice.storage().ref(MESSAGE_PATH.replace("0.webp", "4.webp")),
          new Uint8Array([1]),
          {contentType: "image/webp"},
        ),
      );
    });

    test("allows bounded owner pin creation but no direct read", async () => {
      const alice = requireRules().authenticatedContext("alice");
      const ref = alice.storage().ref(PIN_PATH);
      await assertSucceeds(
        upload(ref, new Uint8Array([1]), {contentType: "image/webp"}),
      );
      await assertFails(ref.getDownloadURL());
      await assertFails(ref.delete());
    });

    test("denies every unauthenticated image operation", async () => {
      const guest = requireRules().unauthenticatedContext();
      const ref = guest.storage().ref(MESSAGE_PATH);
      await assertFails(
        upload(ref, new Uint8Array([1]), {contentType: "image/webp"}),
      );
      await assertFails(ref.getDownloadURL());
    });
  },
);

function requireRules(): RulesTestEnvironment {
  if (rules === undefined) {
    throw new Error("Storage Rules are not initialized.");
  }
  return rules;
}

function upload(
  reference: firebase.storage.Reference,
  bytes: Uint8Array,
  metadata: firebase.storage.UploadMetadata,
): Promise<firebase.storage.UploadTaskSnapshot> {
  return reference.put(bytes, metadata).then((snapshot) => snapshot);
}
