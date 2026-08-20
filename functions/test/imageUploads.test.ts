/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {
  IMAGE_UPLOAD_ORPHAN_GRACE_MILLIS,
  imageUploadId,
} from "../src/imageUploads";
import {
  sweepAsiaOrphanImageUploads,
  sweepEuropeOrphanImageUploads,
  sweepNorthAmericaOrphanImageUploads,
  trackAsiaImageUpload,
  trackEuropeImageUpload,
  trackNorthAmericaImageUpload,
} from "../src/imageUploadTriggers";

const PATH = "images/pins/test-place/alice/" +
  "00000000-0000-700a-800b-000000000001.webp";

test("derives a stable tracker ID from an immutable image path", () => {
  assert.match(imageUploadId(PATH), /^[0-9a-f]{64}$/);
  assert.equal(imageUploadId(PATH), imageUploadId(PATH));
  assert.throws(() => imageUploadId("other/path.webp"));
  assert.equal(IMAGE_UPLOAD_ORPHAN_GRACE_MILLIS, 86_400_000);
});

test("binds finalize triggers to each regional bucket", () => {
  assert.deepEqual(triggerRoute(trackAsiaImageUpload), {
    bucket: "world-notes-prod.firebasestorage.app",
    region: "asia-northeast1",
  });
  assert.deepEqual(triggerRoute(trackNorthAmericaImageUpload), {
    bucket: "world-notes-prod-north-america",
    region: "us-central1",
  });
  assert.deepEqual(triggerRoute(trackEuropeImageUpload), {
    bucket: "world-notes-prod-europe",
    region: "europe-west1",
  });
});

test("runs one hourly orphan sweeper in every world region", () => {
  assert.equal(scheduleRegion(sweepAsiaOrphanImageUploads), "asia-northeast1");
  assert.equal(
    scheduleRegion(sweepNorthAmericaOrphanImageUploads),
    "us-central1",
  );
  assert.equal(scheduleRegion(sweepEuropeOrphanImageUploads), "europe-west1");
});

interface EventFunctionShape {
  readonly __endpoint: {
    readonly region?: readonly string[];
    readonly eventTrigger?: {
      readonly eventFilters?: Record<string, string>;
    };
  };
}

interface ScheduleFunctionShape {
  readonly __endpoint: {readonly region?: readonly string[]};
}

function triggerRoute(value: unknown) {
  const endpoint = (value as EventFunctionShape).__endpoint;
  return {
    bucket: endpoint.eventTrigger?.eventFilters?.bucket,
    region: endpoint.region?.[0],
  };
}

function scheduleRegion(value: unknown): string | undefined {
  return (value as ScheduleFunctionShape).__endpoint.region?.[0];
}
