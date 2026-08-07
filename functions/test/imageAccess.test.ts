/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {DocumentSnapshot, Timestamp} from "firebase-admin/firestore";

import {
  canAccessMessageImage,
  canAccessPlaceImage,
  getImageAccessUrls,
  IMAGE_ACCESS_STATUS,
  parseImageStorageRoute,
  placeReferencesPinImage,
  SIGNED_IMAGE_URL_LIFETIME_MILLIS,
  SIGNED_IMAGE_URL_MAX_PATHS,
} from "../src/imageAccess";
import {pinImageModerationInputHash} from "../src/pinImageCandidate";

const PLACE_ID = "test-place";
const MESSAGE_ID = "00000000-0000-700a-800b-000000000001";
const MESSAGE_PATH =
  `images/messages/${PLACE_ID}/alice/${MESSAGE_ID}/0.webp`;
const PIN_PATH =
  `images/pins/${PLACE_ID}/alice/00000000-0000-700a-800b-000000000002.webp`;
const NOW = Timestamp.fromMillis(1_000_000);

test("parses only canonical immutable image paths", () => {
  assert.deepEqual(parseImageStorageRoute(MESSAGE_PATH), {
    kind: "message",
    storagePath: MESSAGE_PATH,
    placeId: PLACE_ID,
    ownerUid: "alice",
    messageId: MESSAGE_ID,
  });
  assert.deepEqual(parseImageStorageRoute(PIN_PATH), {
    kind: "pin",
    storagePath: PIN_PATH,
    placeId: PLACE_ID,
    ownerUid: "alice",
  });
  assert.throws(
    () => parseImageStorageRoute("images/messages/test/../secret.webp"),
    /Invalid image storage path/,
  );
  assert.throws(
    () => parseImageStorageRoute(
      `images/messages/${PLACE_ID}/alice/${MESSAGE_ID}/4.webp`,
    ),
    /Invalid image storage path/,
  );
});

test("allows an active public pin only when the note references it", () => {
  const place = snapshot(activePlace({pinImageStoragePath: PIN_PATH}));
  assert.equal(
    canAccessPlaceImage(place, null, "viewer", NOW.toMillis(), false),
    true,
  );
  assert.equal(
    canAccessPlaceImage(place, null, "viewer", NOW.toMillis(), true),
    false,
  );
  assert.equal(
    canAccessPlaceImage(
      snapshot(activePlace({isModerationHidden: true})),
      null,
      "viewer",
      NOW.toMillis(),
      false,
    ),
    false,
  );
});

test("treats a valid pending pin candidate as the current image", () => {
  const pending = snapshot(activePlace({
    pinImageStoragePath: "images/pins/test-place/alice/" +
      "00000000-0000-700a-800b-000000000003.webp",
    pinImageCandidate: {
      storagePath: PIN_PATH,
      inputHash: pinImageModerationInputHash(PIN_PATH),
      requestedByUid: "alice",
      moderationAction: "pending",
      createdAt: NOW,
    },
  }));

  assert.equal(placeReferencesPinImage(pending, PIN_PATH), true);
});

test("requires membership or maintenance for private note images", () => {
  const place = snapshot(activePlace({visibility: "private"}));
  assert.equal(
    canAccessPlaceImage(place, snapshot(null), "viewer", NOW.toMillis(), false),
    false,
  );
  assert.equal(
    canAccessPlaceImage(
      place,
      snapshot({viaPasswordVersion: 1}),
      "viewer",
      NOW.toMillis(),
      false,
    ),
    true,
  );
  assert.equal(
    canAccessPlaceImage(place, null, "alice", NOW.toMillis(), false),
    true,
  );
});

test(
  "requires exact visible message references and hides other schedules",
  () => {
    const route = parseImageStorageRoute(MESSAGE_PATH);
    assert.equal(route.kind, "message");
    if (route.kind !== "message") throw new Error("Expected message route.");
    const place = snapshot(activePlace());
    const publicMessage = snapshot(messageData());
    assert.equal(
      canAccessMessageImage(
        place,
        null,
        publicMessage,
        route,
        "viewer",
        NOW.toMillis(),
        false,
        false,
      ),
      true,
    );
    assert.equal(
      canAccessMessageImage(
        place,
        null,
        snapshot(messageData({isPubliclyVisible: false})),
        route,
        "viewer",
        NOW.toMillis(),
        false,
        false,
      ),
      false,
    );
    assert.equal(
      canAccessMessageImage(
        place,
        null,
        snapshot(messageData({isPubliclyVisible: false})),
        route,
        "alice",
        NOW.toMillis(),
        false,
        false,
      ),
      true,
    );
    assert.equal(
      canAccessMessageImage(
        place,
        null,
        snapshot(messageData({moderationAction: "hidden"})),
        route,
        "viewer",
        NOW.toMillis(),
        false,
        false,
      ),
      false,
    );
    assert.equal(
      canAccessMessageImage(
        place,
        null,
        publicMessage,
        {...route, storagePath: MESSAGE_PATH.replace("0.webp", "1.webp")},
        "viewer",
        NOW.toMillis(),
        false,
        false,
      ),
      false,
    );
  },
);

test(
  "uses a 24-hour URL lifetime and every regional callable deployment",
  () => {
    assert.equal(SIGNED_IMAGE_URL_LIFETIME_MILLIS, 86_400_000);
    assert.equal(SIGNED_IMAGE_URL_MAX_PATHS, 50);
    assert.deepEqual(IMAGE_ACCESS_STATUS, {
      available: "available",
      unavailable: "unavailable",
    });
    assert.deepEqual(getImageAccessUrls.__endpoint.region, [
      "asia-northeast1",
      "us-central1",
      "europe-west1",
    ]);
  },
);

function activePlace(overrides: Record<string, unknown> = {}) {
  return {
    createdByUserId: "alice",
    maintainerIds: ["alice"],
    visibility: "public",
    passwordVersion: 1,
    isArchived: false,
    isModerationHidden: false,
    publishAt: Timestamp.fromMillis(NOW.toMillis() - 1),
    expiresAt: Timestamp.fromMillis(NOW.toMillis() + 1),
    ...overrides,
  };
}

function messageData(overrides: Record<string, unknown> = {}) {
  return {
    userId: "alice",
    imageStoragePaths: [MESSAGE_PATH],
    isDeleted: false,
    isVisible: true,
    isPubliclyVisible: true,
    moderationAction: "pending",
    ...overrides,
  };
}

function snapshot(data: Record<string, unknown> | null): DocumentSnapshot {
  return {
    exists: data !== null,
    get: (field: string) => data?.[field],
  } as unknown as DocumentSnapshot;
}
