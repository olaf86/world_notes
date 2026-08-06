/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {Timestamp} from "firebase-admin/firestore";

import {
  isNoteAdministratorInvitationExpired,
  newNoteAdministratorInvitationData,
  noteAdministratorInvitationId,
  NOTE_ADMINISTRATOR_INVITE_LIFETIME_MILLIS,
  NOTE_ADMINISTRATOR_INVITE_STATUS,
  NOTE_ADMINISTRATOR_MAX_ACTIVE,
  NOTE_ADMINISTRATOR_MAX_PENDING_INVITES,
  parseNoteAdministratorInvitation,
  signNoteAdministratorInvitationToken,
  terminalNoteAdministratorInvitation,
  verifyNoteAdministratorInvitationToken,
} from "../src/noteAdministratorInvitations";
import {
  archivedNoteAdministratorInvitationRevocationHandler,
  EXPIRE_NOTE_ADMINISTRATOR_INVITATION_JOB,
  noteAdministratorInvitationExpirationHandler,
  REVOKE_ARCHIVED_NOTE_ADMINISTRATOR_INVITATIONS_JOB,
} from "../src/noteAdministratorInviteCleanup";
import {
  routeAsiaNoteAdministratorInviteNotification,
  routeEuropeNoteAdministratorInviteNotification,
  routeNorthAmericaNoteAdministratorInviteNotification,
} from "../src/noteAdministratorInviteNotifications";

const SIGNING_KEY = "test-signing-key-material-that-is-at-least-32-bytes";
const NONCE = "A".repeat(43);

test("administrator and pending invitation limits are both ten", () => {
  assert.equal(NOTE_ADMINISTRATOR_MAX_ACTIVE, 10);
  assert.equal(NOTE_ADMINISTRATOR_MAX_PENDING_INVITES, 10);
});

test("administrator invitation IDs bind a note and target user", () => {
  const first = noteAdministratorInvitationId("test-place", "target-user");

  assert.match(first, /^[0-9a-f]{64}$/);
  assert.equal(
    first,
    noteAdministratorInvitationId("test-place", "target-user"),
  );
  assert.notEqual(
    first,
    noteAdministratorInvitationId("test-place", "another-user"),
  );
});

test("signed invitation tokens bind world, revision, and nonce", () => {
  const inviteId = noteAdministratorInvitationId(
    "test-place",
    "target-user",
  );
  const token = signNoteAdministratorInvitationToken({
    version: 1,
    worldId: "northAmerica",
    inviteId,
    revision: 3,
    nonce: NONCE,
  }, SIGNING_KEY);

  assert.deepEqual(
    verifyNoteAdministratorInvitationToken(token, SIGNING_KEY),
    {
      version: 1,
      worldId: "northAmerica",
      inviteId,
      revision: 3,
      nonce: NONCE,
    },
  );
  assert.throws(
    () => verifyNoteAdministratorInvitationToken(
      token.replace("northAmerica", "europe"),
      SIGNING_KEY,
    ),
    /token is invalid/,
  );
  assert.throws(
    () => verifyNoteAdministratorInvitationToken(token, "x".repeat(32)),
    /token is invalid/,
  );
});

test("pending invitations use one exact seven-day deadline", () => {
  const now = Timestamp.fromMillis(1_000);
  const invitation = newNoteAdministratorInvitationData({
    placeId: "test-place",
    targetUid: "target-user",
    invitedByUid: "inviting-user",
    nonce: NONCE,
    revision: 1,
  }, now);

  assert.equal(invitation.status, NOTE_ADMINISTRATOR_INVITE_STATUS.pending);
  assert.equal(
    invitation.expiresAt.toMillis(),
    now.toMillis() + NOTE_ADMINISTRATOR_INVITE_LIFETIME_MILLIS,
  );
  assert.equal(
    isNoteAdministratorInvitationExpired(
      invitation,
      Timestamp.fromMillis(invitation.expiresAt.toMillis() - 1),
    ),
    false,
  );
  assert.equal(
    isNoteAdministratorInvitationExpired(invitation, invitation.expiresAt),
    true,
  );
});

test("terminal invitations retain one terminal time and TTL deadline", () => {
  const pending = newNoteAdministratorInvitationData({
    placeId: "test-place",
    targetUid: "target-user",
    invitedByUid: "inviting-user",
    nonce: NONCE,
    revision: 1,
  }, Timestamp.fromMillis(1_000));
  const terminalAt = Timestamp.fromMillis(2_000);
  const accepted = terminalNoteAdministratorInvitation(
    pending,
    NOTE_ADMINISTRATOR_INVITE_STATUS.accepted,
    terminalAt,
  );

  assert.equal(accepted.terminalAt?.toMillis(), terminalAt.toMillis());
  assert.ok(accepted.purgeAt !== null);
  assert.ok(accepted.purgeAt.toMillis() > terminalAt.toMillis());
  assert.doesNotThrow(() => parseNoteAdministratorInvitation(accepted));
  assert.throws(
    () => parseNoteAdministratorInvitation({
      ...accepted,
      terminalAt: null,
    }),
    /Terminal administrator invitation is invalid/,
  );
});

test("persisted invitation identity must match its note and target", () => {
  const invitation = newNoteAdministratorInvitationData({
    placeId: "test-place",
    targetUid: "target-user",
    invitedByUid: "inviting-user",
    nonce: NONCE,
    revision: 1,
  }, Timestamp.fromMillis(1_000));

  assert.throws(
    () => parseNoteAdministratorInvitation({
      ...invitation,
      targetUid: "another-user",
    }),
    /identity is invalid/,
  );
});

test("expiration cleanup is registered under its explicit job type", () => {
  assert.equal(
    noteAdministratorInvitationExpirationHandler.queue,
    "firestore",
  );
  assert.equal(
    noteAdministratorInvitationExpirationHandler.jobType,
    EXPIRE_NOTE_ADMINISTRATOR_INVITATION_JOB,
  );
  assert.equal(
    archivedNoteAdministratorInvitationRevocationHandler.queue,
    "firestore",
  );
  assert.equal(
    archivedNoteAdministratorInvitationRevocationHandler.jobType,
    REVOKE_ARCHIVED_NOTE_ADMINISTRATOR_INVITATIONS_JOB,
  );
});

test("notification triggers are bound to every world database", () => {
  assert.equal(
    triggerDatabase(routeAsiaNoteAdministratorInviteNotification),
    "(default)",
  );
  assert.equal(
    triggerDatabase(routeNorthAmericaNoteAdministratorInviteNotification),
    "north-america",
  );
  assert.equal(
    triggerDatabase(routeEuropeNoteAdministratorInviteNotification),
    "europe",
  );
});

interface EventFunctionShape {
  readonly __endpoint: {
    readonly eventTrigger?: {
      readonly eventFilters?: Record<string, string>;
    };
  };
}

function triggerDatabase(value: unknown): string | undefined {
  return (value as EventFunctionShape).__endpoint.eventTrigger
    ?.eventFilters?.database;
}
