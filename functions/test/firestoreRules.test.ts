/* eslint-disable require-jsdoc, valid-jsdoc */

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
import "firebase/compat/firestore";

const hasFirestoreEmulator =
  process.env.FIRESTORE_EMULATOR_HOST !== undefined;

let applicationRules: RulesTestEnvironment | undefined;
let lockedWorldRules: RulesTestEnvironment | undefined;

describe(
  "Firestore Security Rules",
  {skip: !hasFirestoreEmulator, concurrency: false},
  () => {
    before(async () => {
      const [applicationRulesSource, lockedWorldRulesSource] =
        await Promise.all([
          readFile(
            resolve(process.cwd(), "../firestore.rules"),
            "utf8",
          ),
          readFile(
            resolve(process.cwd(), "../firestore.named.locked.rules"),
            "utf8",
          ),
        ]);

      applicationRules = await initializeTestEnvironment({
        projectId: "demo-world-notes-application-rules",
        firestore: {rules: applicationRulesSource},
      });
      lockedWorldRules = await initializeTestEnvironment({
        projectId: "demo-world-notes-locked-world-rules",
        firestore: {rules: lockedWorldRulesSource},
      });
    });

    beforeEach(async () => {
      await Promise.all([
        requireApplicationRules().clearFirestore(),
        requireLockedWorldRules().clearFirestore(),
      ]);
    });

    after(async () => {
      await Promise.all([
        applicationRules?.cleanup(),
        lockedWorldRules?.cleanup(),
      ]);
    });

    describe("private account data", {concurrency: false}, () => {
      test("allows a signed-in user to read their own account", async () => {
        await seedApplicationDocument("users/alice", validUser("Alice"));
        const alice = requireApplicationRules().authenticatedContext("alice");

        await assertSucceeds(alice.firestore().doc("users/alice").get());
      });

      test("denies reading another user's account", async () => {
        await seedApplicationDocument("users/alice", validUser("Alice"));
        const bob = requireApplicationRules().authenticatedContext("bob");

        await assertFails(bob.firestore().doc("users/alice").get());
      });

      test("denies unauthenticated account reads", async () => {
        await seedApplicationDocument("users/alice", validUser("Alice"));
        const guest = requireApplicationRules().unauthenticatedContext();

        await assertFails(guest.firestore().doc("users/alice").get());
      });

      test("denies direct creation of the owner's account", async () => {
        const alice = requireApplicationRules().authenticatedContext("alice");

        await assertFails(
          alice.firestore().doc("users/alice").set(validUser("Alice")),
        );
      });

      test("denies creating an account for another UID", async () => {
        const alice = requireApplicationRules().authenticatedContext("alice");

        await assertFails(
          alice.firestore().doc("users/bob").set(validUser("Bob")),
        );
      });

      test("denies undefined fields on account creation", async () => {
        const alice = requireApplicationRules().authenticatedContext("alice");

        await assertFails(
          alice.firestore().doc("users/alice").set({
            ...validUser("Alice"),
            isAdmin: true,
          }),
        );
      });

      test("denies owner account updates and deletes", async () => {
        await seedApplicationDocument("users/alice", validUser("Alice"));
        const alice = requireApplicationRules().authenticatedContext("alice");

        await assertFails(
          alice.firestore().doc("users/alice").update({isAdmin: true}),
        );
        await assertFails(alice.firestore().doc("users/alice").delete());
      });
    });

    describe("home routing markers", {concurrency: false}, () => {
      test("allows only the owner to get the exact marker", async () => {
        await seedApplicationDocument("userHomes/alice", validUserHome());
        const alice = requireApplicationRules().authenticatedContext("alice");
        const bob = requireApplicationRules().authenticatedContext("bob");
        const guest = requireApplicationRules().unauthenticatedContext();

        await assertSucceeds(
          alice.firestore().doc("userHomes/alice").get(),
        );
        await assertFails(bob.firestore().doc("userHomes/alice").get());
        await assertFails(guest.firestore().doc("userHomes/alice").get());
      });

      test("denies marker listing and every client write", async () => {
        await seedApplicationDocument("userHomes/alice", validUserHome());
        const alice = requireApplicationRules().authenticatedContext("alice");

        await assertFails(alice.firestore().collection("userHomes").get());
        await assertFails(
          alice.firestore().doc("userHomes/bob").set(validUserHome()),
        );
        await assertFails(
          alice.firestore().doc("userHomes/alice").update({world: "europe"}),
        );
        await assertFails(alice.firestore().doc("userHomes/alice").delete());
      });

      test(
        "denies all client access to entitlement and usage mirrors",
        async () => {
          await Promise.all([
            seedApplicationDocument("userEntitlements/alice", {
              isPremium: false,
              updatedAt: firebase.firestore.Timestamp.now(),
            }),
            seedApplicationDocument("userUsage/alice", {
              activeNoteCount: 0,
              updatedAt: firebase.firestore.Timestamp.now(),
            }),
          ]);
          const alice =
            requireApplicationRules().authenticatedContext("alice");

          await assertFails(
            alice.firestore().doc("userEntitlements/alice").get(),
          );
          await assertFails(
            alice.firestore().doc("userUsage/alice").get(),
          );
          await assertFails(
            alice.firestore().doc("userEntitlements/alice").set({
              isPremium: true,
            }),
          );
          await assertFails(
            alice.firestore().doc("userUsage/alice").update({
              activeNoteCount: 1000000,
            }),
          );
        },
      );
    });

    describe("public profiles", {concurrency: false}, () => {
      test("allows authenticated profile reads", async () => {
        await seedApplicationDocument(
          "publicProfiles/alice",
          storedPublicProfile("Alice"),
        );
        const bob = requireApplicationRules().authenticatedContext("bob");

        await assertSucceeds(
          bob.firestore().doc("publicProfiles/alice").get(),
        );
      });

      test("denies unauthenticated profile reads", async () => {
        await seedApplicationDocument(
          "publicProfiles/alice",
          storedPublicProfile("Alice"),
        );
        const guest = requireApplicationRules().unauthenticatedContext();

        await assertFails(
          guest.firestore().doc("publicProfiles/alice").get(),
        );
      });

      test(
        "denies direct owner creation of a public profile",
        async () => {
          const alice =
            requireApplicationRules().authenticatedContext("alice");

          await assertFails(
            alice.firestore().doc("publicProfiles/alice").set({
              displayName: "Alice",
              photoUrl: null,
              photoVersion: 1,
              followerCount: 0,
              followingCount: 0,
              createdAt: firebase.firestore.FieldValue.serverTimestamp(),
              updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
            }),
          );
        },
      );

      test("denies self-assigned public profile counters", async () => {
        const alice = requireApplicationRules().authenticatedContext("alice");

        await assertFails(
          alice.firestore().doc("publicProfiles/alice").set({
            displayName: "Alice",
            photoUrl: null,
            photoVersion: 1,
            followerCount: 100,
            followingCount: 0,
            createdAt: firebase.firestore.FieldValue.serverTimestamp(),
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
          }),
        );
      });

      test("denies counter changes in an owner profile update", async () => {
        await seedApplicationDocument(
          "publicProfiles/alice",
          storedPublicProfile("Alice"),
        );
        const alice = requireApplicationRules().authenticatedContext("alice");

        await assertFails(
          alice.firestore().doc("publicProfiles/alice").update({
            followerCount: 1,
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
          }),
        );
      });

      test("denies owner display-field updates and deletes", async () => {
        await seedApplicationDocument(
          "publicProfiles/alice",
          storedPublicProfile("Alice"),
        );
        const alice = requireApplicationRules().authenticatedContext("alice");

        await assertFails(
          alice.firestore().doc("publicProfiles/alice").update({
            displayName: "Mallory",
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
          }),
        );
        await assertFails(
          alice.firestore().doc("publicProfiles/alice").delete(),
        );
      });
    });

    describe("global operation status", {concurrency: false}, () => {
      test(
        "allows only the bound owner to get an exact operation",
        async () => {
          await seedApplicationDocument(
            "globalOperations/9c981950-3f3b-4db0-8505-3c5b7789ac83",
            validGlobalOperation("alice"),
          );
          const alice =
            requireApplicationRules().authenticatedContext("alice");
          const bob = requireApplicationRules().authenticatedContext("bob");
          const guest = requireApplicationRules().unauthenticatedContext();
          const path =
            "globalOperations/9c981950-3f3b-4db0-8505-3c5b7789ac83";

          await assertSucceeds(alice.firestore().doc(path).get());
          await assertFails(bob.firestore().doc(path).get());
          await assertFails(guest.firestore().doc(path).get());
        },
      );

      test("denies owner listing and every client write", async () => {
        const operationId = "9c981950-3f3b-4db0-8505-3c5b7789ac83";
        const path = `globalOperations/${operationId}`;
        await seedApplicationDocument(path, validGlobalOperation("alice"));
        const alice = requireApplicationRules().authenticatedContext("alice");

        await assertFails(
          alice.firestore().collection("globalOperations").get(),
        );
        await assertFails(
          alice.firestore().doc("globalOperations/new-operation").set(
            validGlobalOperation("alice"),
          ),
        );
        await assertFails(
          alice.firestore().doc(path).update({status: "complete"}),
        );
        await assertFails(alice.firestore().doc(path).delete());
      });
    });

    describe("bootstrap write guard", {concurrency: false}, () => {
      test(
        "allows an owner to mark a notice read after bootstrap",
        async () => {
          await Promise.all([
            seedApplicationDocument("userHomes/alice", validUserHome()),
            seedApplicationDocument(
              "users/alice/notices/notice-1",
              validNotice(),
            ),
          ]);
          const alice =
            requireApplicationRules().authenticatedContext("alice");

          await assertSucceeds(
            alice.firestore().doc("users/alice/notices/notice-1").update({
              readAt: firebase.firestore.FieldValue.serverTimestamp(),
            }),
          );
        },
      );

      test("denies a stateful write before bootstrap", async () => {
        await seedApplicationDocument(
          "users/alice/notices/notice-1",
          validNotice(),
        );
        const alice = requireApplicationRules().authenticatedContext("alice");

        await assertFails(
          alice.firestore().doc("users/alice/notices/notice-1").update({
            readAt: firebase.firestore.FieldValue.serverTimestamp(),
          }),
        );
      });
    });

    describe("notes and messages", {concurrency: false}, () => {
      test("allows an authenticated user to get a public note", async () => {
        await seedApplicationDocument("places/tokyo", activePublicPlace());
        const bob = requireApplicationRules().authenticatedContext("bob");

        await assertSucceeds(bob.firestore().doc("places/tokyo").get());
      });

      test("denies a moderation-hidden note", async () => {
        await seedApplicationDocument("places/tokyo", {
          ...activePublicPlace(),
          isModerationHidden: true,
        });
        const bob = requireApplicationRules().authenticatedContext("bob");

        await assertFails(bob.firestore().doc("places/tokyo").get());
      });

      test("denies a note when either user has blocked the other", async () => {
        await Promise.all([
          seedApplicationDocument("places/tokyo", activePublicPlace()),
          seedApplicationDocument("users/alice/blockedUsers/bob", {
            blockedAt: firebase.firestore.Timestamp.now(),
          }),
        ]);
        const bob = requireApplicationRules().authenticatedContext("bob");

        await assertFails(bob.firestore().doc("places/tokyo").get());
      });

      test("denies direct note creation", async () => {
        const alice = requireApplicationRules().authenticatedContext("alice");

        await assertFails(
          alice.firestore().doc("places/tokyo").set(activePublicPlace()),
        );
      });

      test(
        "allows reading a visible message in an accessible note",
        async () => {
          await Promise.all([
            seedApplicationDocument("places/tokyo", activePublicPlace()),
            seedApplicationDocument("places/tokyo/messages/hello", {
              userId: "alice",
              isVisible: true,
              isPubliclyVisible: true,
            }),
          ]);
          const bob = requireApplicationRules().authenticatedContext("bob");

          await assertSucceeds(
            bob.firestore().doc("places/tokyo/messages/hello").get(),
          );
        },
      );

      test(
        "keeps a non-public message visible only to its sender",
        async () => {
          await Promise.all([
            seedApplicationDocument("places/tokyo", activePublicPlace()),
            seedApplicationDocument("places/tokyo/messages/pending", {
              userId: "alice",
              isVisible: true,
              isPubliclyVisible: false,
            }),
          ]);
          const alice =
            requireApplicationRules().authenticatedContext("alice");
          const bob = requireApplicationRules().authenticatedContext("bob");

          await assertSucceeds(
            alice.firestore().doc("places/tokyo/messages/pending").get(),
          );
          await assertFails(
            bob.firestore().doc("places/tokyo/messages/pending").get(),
          );
        },
      );
    });

    describe("server-only data", {concurrency: false}, () => {
      test("denies client access to moderation audit logs", async () => {
        await seedApplicationDocument("moderationAuditLogs/log", {
          action: "allow",
        });
        const alice = requireApplicationRules().authenticatedContext("alice");

        await assertFails(
          alice.firestore().doc("moderationAuditLogs/log").get(),
        );
        await assertFails(
          alice.firestore().doc("moderationAuditLogs/new-log").set({
            action: "allow",
          }),
        );
      });
    });

    describe("provisioning worlds", {concurrency: false}, () => {
      test("denies authenticated reads while a world is locked", async () => {
        await seedLockedWorldDocument("places/north-america", {title: "Test"});
        const alice = requireLockedWorldRules().authenticatedContext("alice");

        await assertFails(
          alice.firestore().doc("places/north-america").get(),
        );
      });

      test("denies authenticated writes while a world is locked", async () => {
        const alice = requireLockedWorldRules().authenticatedContext("alice");

        await assertFails(
          alice.firestore().doc("places/north-america").set({title: "Test"}),
        );
      });
    });
  },
);

/** Returns the initialized application Rules environment. */
function requireApplicationRules(): RulesTestEnvironment {
  if (applicationRules === undefined) {
    throw new Error("Application Rules test environment is not initialized.");
  }
  return applicationRules;
}

/** Returns the initialized locked-world Rules environment. */
function requireLockedWorldRules(): RulesTestEnvironment {
  if (lockedWorldRules === undefined) {
    throw new Error("Locked-world Rules test environment is not initialized.");
  }
  return lockedWorldRules;
}

/** Seeds one application document while bypassing client Rules. */
async function seedApplicationDocument(
  path: string,
  data: firebase.firestore.DocumentData,
): Promise<void> {
  await requireApplicationRules().withSecurityRulesDisabled(
    async (context) => {
      await context.firestore().doc(path).set(data);
    },
  );
}

/** Seeds one locked-world document while bypassing client Rules. */
async function seedLockedWorldDocument(
  path: string,
  data: firebase.firestore.DocumentData,
): Promise<void> {
  await requireLockedWorldRules().withSecurityRulesDisabled(
    async (context) => {
      await context.firestore().doc(path).set(data);
    },
  );
}

/** Creates a valid private user document for a test. */
function validUser(displayName: string): firebase.firestore.DocumentData {
  return {
    displayName,
    email: `${displayName.toLowerCase()}@example.com`,
    photoUrl: null,
  };
}

/** Creates an immutable home-routing marker for Rules tests. */
function validUserHome(): firebase.firestore.DocumentData {
  return {
    world: "asia",
    epoch: 1,
    createdAt: firebase.firestore.Timestamp.now(),
  };
}

/** Creates a valid owner-readable notice. */
function validNotice(): firebase.firestore.DocumentData {
  return {
    category: "account",
    severity: "info",
    title: "Welcome",
    body: "Your account is ready.",
    action: null,
    sourceType: null,
    sourceId: null,
    createdAt: firebase.firestore.Timestamp.now(),
    readAt: null,
  };
}

/** Creates a trusted server-written global operation status. */
function validGlobalOperation(
  ownerUid: string,
): firebase.firestore.DocumentData {
  const now = firebase.firestore.Timestamp.now();
  return {
    operationId: "9c981950-3f3b-4db0-8505-3c5b7789ac83",
    operationType: "setLanguagePreference",
    entityId: ownerUid,
    revision: 1,
    authorityWorld: "asia",
    ownerUid,
    payloadHash: "a".repeat(64),
    status: "complete",
    acceptedAt: now,
    worldCatalogVersion: 1,
    requiredWorlds: ["asia"],
    worldAcks: {asia: {revision: 1, acknowledgedAt: now}},
    createdAt: now,
    updatedAt: now,
    completedAt: now,
    expireAt: now,
  };
}

/** Creates a stored public profile for read and update tests. */
function storedPublicProfile(
  displayName: string,
): firebase.firestore.DocumentData {
  const now = firebase.firestore.Timestamp.now();
  return {
    displayName,
    photoUrl: null,
    photoVersion: 1,
    followerCount: 0,
    followingCount: 0,
    createdAt: now,
    updatedAt: now,
  };
}

/** Creates the minimum note fields used by Rules helper functions. */
function activePublicPlace(): firebase.firestore.DocumentData {
  const now = Date.now();
  return {
    createdByUserId: "alice",
    maintainerIds: ["alice"],
    visibility: "public",
    passwordVersion: 1,
    isArchived: false,
    isModerationHidden: false,
    isOpen: true,
    publishAt: firebase.firestore.Timestamp.fromMillis(now - 60_000),
    expiresAt: firebase.firestore.Timestamp.fromMillis(now + 60_000),
  };
}
