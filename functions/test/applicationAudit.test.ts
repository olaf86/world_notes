import assert from "node:assert/strict";
import test from "node:test";

import type {CallableRequest} from "firebase-functions/v2/https";

import {
  applicationAuditEvent,
  auditOutcomeForError,
  callableAuditContext,
} from "../src/applicationAudit";

test("captures identifiers without logging sensitive request fields", () => {
  const request = {
    app: {appId: "1:123:ios:abc"},
    auth: {
      uid: "actor-1",
      token: {firebase: {sign_in_provider: "google.com"}},
    },
    data: {
      worldId: "asia",
      placeId: "place-1",
      messageId: "message-1",
      operationId: "operation-1",
      content: "must not be logged",
      password: "must not be logged",
      token: "must not be logged",
      liked: true,
      reasonCode: "spam",
    },
    rawRequest: {
      headers: {
        "function-execution-id": "execution-1",
        "x-cloud-trace-context": "trace-1/1;o=1",
      },
    },
  } as unknown as CallableRequest<Record<string, unknown>>;

  const context = callableAuditContext(request, "message.report", 1_000);
  assert.deepEqual(context.identifiers, {
    operationId: "operation-1",
    placeId: "place-1",
    messageId: "message-1",
  });
  assert.deepEqual(context.parameters, {liked: true, reasonCode: "spam"});
  assert.equal(context.actorUid, "actor-1");
  assert.equal(context.appId, "1:123:ios:abc");
  assert.equal(context.authProvider, "google.com");
  assert.equal(context.requestId, "execution-1");
  assert.equal(context.traceContext, "trace-1/1;o=1");
  assert.equal("content" in context.identifiers, false);
  assert.equal("password" in context.identifiers, false);
  assert.equal("token" in context.identifiers, false);
});

test("captures administrator action metadata without its reason text", () => {
  const request = {
    auth: {uid: "admin-1", token: {}},
    app: undefined,
    data: {
      targetUid: "target-1",
      action: {type: "setBan", durationDays: 30},
      reason: "private administrator notes must not be logged",
      reference: "private case reference must not be logged",
    },
    rawRequest: {headers: {}},
  } as unknown as CallableRequest<Record<string, unknown>>;

  const context = callableAuditContext(
    request,
    "admin.accountSafety.update",
    2_000,
  );
  assert.deepEqual(context.identifiers, {targetUid: "target-1"});
  assert.deepEqual(context.parameters, {
    actionType: "setBan",
    actionDurationDays: 30,
  });
});

test("classifies request failures separately from internal errors", () => {
  assert.equal(
    auditOutcomeForError({code: "permission-denied"}),
    "denied",
  );
  assert.equal(
    auditOutcomeForError({code: "invalid-argument"}),
    "rejected",
  );
  assert.equal(auditOutcomeForError(new Error("boom")), "error");
});

test("builds an event with stable reason and duration", () => {
  const context = {
    action: "message.send",
    actorUid: "actor-1",
    appId: null,
    authProvider: null,
    eventId: "event-1",
    identifiers: {placeId: "place-1"},
    parameters: {},
    requestId: null,
    startedAtMillis: 1_000,
    traceContext: null,
  } as const;

  const event = applicationAuditEvent(
    context,
    "denied",
    "asia",
    {
      code: "permission-denied",
      details: {reason: "account-banned"},
    },
    1_125,
  );
  assert.equal(event.eventType, "worldNotesApplicationAudit");
  assert.equal(event.durationMillis, 125);
  assert.equal(event.errorCode, "permission-denied");
  assert.equal(event.reasonCode, "account-banned");
  assert.equal(event.worldId, "asia");
});
