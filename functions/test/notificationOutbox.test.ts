/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {Timestamp} from "firebase-admin/firestore";

import {
  classifyFcmError,
  newNotificationOutboxData,
  notificationEventId,
  NotificationDeliveryHandler,
  NotificationDeliveryHandlerRegistry,
  notificationRetryAt,
  parseNotificationOutbox,
} from "../src/notificationOutbox";
import {
  processAsiaNotificationOutbox,
  processEuropeNotificationOutbox,
  processNorthAmericaNotificationOutbox,
  reconcileAsiaNotificationOutbox,
  reconcileEuropeNotificationOutbox,
  reconcileNorthAmericaNotificationOutbox,
} from "../src/notificationOutboxTriggers";

const CREATED_AT = Timestamp.fromMillis(1_000);
const EXPIRES_AT = Timestamp.fromMillis(
  CREATED_AT.toMillis() + 24 * 60 * 60 * 1000,
);

test("notification event IDs are deterministic and partition-sensitive", () => {
  const input = idInput();
  const eventId = notificationEventId(input);

  assert.equal(notificationEventId({...input}), eventId);
  assert.match(eventId, /^[0-9a-f]{64}$/);
  assert.notEqual(
    notificationEventId({...input, partition: "second"}),
    eventId,
  );
});

test("new outbox data snapshots unique pending recipients", () => {
  const input = eventInput();
  const event = parseNotificationOutbox(
    newNotificationOutboxData(input, CREATED_AT),
    input.eventId,
    "asia",
  );

  assert.equal(event.status, "pending");
  assert.deepEqual(
    event.recipientUids,
    ["test-recipient-a", "test-recipient-b"],
  );
  assert.deepEqual(event.recipientResults, {
    "test-recipient-a": "pending",
    "test-recipient-b": "pending",
  });
  assert.throws(
    () => newNotificationOutboxData({
      ...input,
      recipientUids: ["duplicate", "duplicate"],
    }, CREATED_AT),
    /duplicates/,
  );
  assert.throws(
    () => newNotificationOutboxData({
      ...input,
      sourcePath: "places/test-place/messages",
    }, CREATED_AT),
    /sourcePath/,
  );
  assert.throws(
    () => newNotificationOutboxData({
      ...input,
      sourcePath: `places/${"あ".repeat(400)}`,
    }, CREATED_AT),
    /sourcePath/,
  );
});

test("notification retry includes the final due time", () => {
  const neutralJitter = 0.5;
  assert.equal(
    notificationRetryAt(1, CREATED_AT, EXPIRES_AT, neutralJitter).toMillis(),
    CREATED_AT.toMillis() + 60 * 1000,
  );
  assert.equal(
    notificationRetryAt(2, CREATED_AT, EXPIRES_AT, neutralJitter).toMillis(),
    CREATED_AT.toMillis() + 5 * 60 * 1000,
  );
  assert.equal(
    notificationRetryAt(6, CREATED_AT, EXPIRES_AT, neutralJitter).toMillis(),
    EXPIRES_AT.toMillis() - 5 * 60 * 1000,
  );
});

test("FCM results distinguish retry and terminal categories", () => {
  assert.equal(
    classifyFcmError("messaging/registration-token-not-registered"),
    "deleteToken",
  );
  assert.equal(classifyFcmError("messaging/unavailable"), "retry");
  assert.equal(
    classifyFcmError("messaging/invalid-apns-credentials"),
    "deploymentFault",
  );
  assert.equal(
    classifyFcmError("messaging/payload-size-limit-exceeded"),
    "payloadFault",
  );
});

test("handler registry requires one owner per event type", () => {
  const handler = testHandler();
  const registry = new NotificationDeliveryHandlerRegistry([handler]);

  assert.equal(registry.require("notifyTestRecipient"), handler);
  assert.throws(() => registry.require("unknownEvent"), /No notification/);
  assert.throws(
    () => new NotificationDeliveryHandlerRegistry([handler, handler]),
    /Duplicate notification/,
  );
});

test("notification workers are routed to all three databases", () => {
  const triggers = [
    [processAsiaNotificationOutbox, "(default)", "asia-northeast1"],
    [processNorthAmericaNotificationOutbox, "north-america", "us-central1"],
    [processEuropeNotificationOutbox, "europe", "europe-west1"],
  ] as const;
  for (const [trigger, database, region] of triggers) {
    assert.equal(triggerDatabase(trigger), database);
    assert.equal(triggerRegion(trigger), region);
    assert.equal(triggerDocument(trigger), "notificationOutbox/{eventId}");
  }

  const schedules = [
    [reconcileAsiaNotificationOutbox, "asia-northeast1"],
    [reconcileNorthAmericaNotificationOutbox, "us-central1"],
    [reconcileEuropeNotificationOutbox, "europe-west1"],
  ] as const;
  for (const [schedule, region] of schedules) {
    assert.equal(scheduleRegion(schedule), region);
  }
});

function idInput() {
  return {
    sourceEventId: "test-source-event",
    ownerWorld: "asia",
    eventType: "notifyTestRecipient",
  };
}

function eventInput() {
  const identity = idInput();
  return {
    ...identity,
    eventId: notificationEventId(identity),
    sourceWorld: "asia",
    entityType: "message",
    entityId: "test-message",
    sourcePath: "places/test-place/messages/test-message",
    recipientUids: ["test-recipient-a", "test-recipient-b"],
    expiresAt: EXPIRES_AT,
  };
}

function testHandler(): NotificationDeliveryHandler {
  return {
    eventType: "notifyTestRecipient",
    deliver: async () => ({recipientResults: {}}),
  };
}

interface EventFunctionShape {
  readonly __endpoint: {
    readonly region?: readonly string[];
    readonly eventTrigger?: {
      readonly eventFilters?: Record<string, string>;
      readonly eventFilterPathPatterns?: Record<string, string>;
    };
  };
}

interface ScheduleFunctionShape {
  readonly __endpoint: {readonly region?: readonly string[]};
}

function triggerDatabase(value: unknown): string | undefined {
  return (value as EventFunctionShape).__endpoint.eventTrigger
    ?.eventFilters?.database;
}

function triggerDocument(value: unknown): string | undefined {
  return (value as EventFunctionShape).__endpoint.eventTrigger
    ?.eventFilterPathPatterns?.document;
}

function triggerRegion(value: unknown): string | undefined {
  return (value as EventFunctionShape).__endpoint.region?.[0];
}

function scheduleRegion(value: unknown): string | undefined {
  return (value as ScheduleFunctionShape).__endpoint.region?.[0];
}
