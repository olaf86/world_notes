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

      test("allows a user to create their own valid account", async () => {
        const alice = requireApplicationRules().authenticatedContext("alice");

        await assertSucceeds(
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
        "allows an owner to create a strictly validated profile",
        async () => {
          const alice =
            requireApplicationRules().authenticatedContext("alice");

          await assertSucceeds(
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
