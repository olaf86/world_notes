import {setGlobalOptions} from "firebase-functions/v2";
import {initializeApp} from "firebase-admin/app";
import {REGION} from "./constants";

initializeApp();
setGlobalOptions({maxInstances: 10, region: REGION});

// Password set/verify functions. They set region explicitly in their own
// options because, being defined during module import (before this file's
// setGlobalOptions runs), the global region would not otherwise apply.
export {setNotePassword, unlockNote} from "./notePassword";

// Authoritative message writes plus the schedule that makes delayed messages
// public at publishAt. Region set in their own options.
export {
  sendMessage,
  deleteMessage,
  cancelScheduledMessage,
  reportMessage,
  setMessageLike,
} from "./messages";
export {aggregatePublishedMessages} from "./messageTriggers";
export {
  adminListModerationReviews,
  adminReviewMessage,
  adminReviewNote,
} from "./adminModeration";
export {
  adminGetAccountSafety,
  adminUpdateAccountSafety,
} from "./adminAccountSafety";

// Invite-link functions (share-link access to private notes). Region set in
// their own options.
export {
  getInviteLink,
  createInviteLink,
  claimInvite,
  revokeInvite,
  revokeNoteAccess,
  grantNoteMaintainer,
  revokeNoteMaintainer,
} from "./invites";

// Push notification preferences and FCM token registration.
export {
  registerFcmToken,
  deleteFcmToken,
  setMyNotesNotificationEnabled,
  setMyNotesNotificationPreviewEnabled,
} from "./notifications";

// Private account preferences and globally replicated profile updates.
export {assignHomeWorld} from "./accountBootstrap";
export {setLanguagePreference, updateDisplayName} from "./userProfile";
export {refreshEntitlement} from "./revenueCatEntitlements";
export {
  syncAsiaProfileSnapshots,
  syncNorthAmericaProfileSnapshots,
  syncEuropeProfileSnapshots,
} from "./creatorProfileSnapshots";
export {
  replicateAsiaGlobalOperation,
  replicateNorthAmericaGlobalOperation,
  replicateEuropeGlobalOperation,
  reconcileAsiaGlobalOperations,
  reconcileNorthAmericaGlobalOperations,
  reconcileEuropeGlobalOperations,
} from "./globalReplicationTriggers";
export {
  processAsiaFirestoreCleanupJob,
  processNorthAmericaFirestoreCleanupJob,
  processEuropeFirestoreCleanupJob,
  processAsiaStorageCleanupJob,
  processNorthAmericaStorageCleanupJob,
  processEuropeStorageCleanupJob,
  reconcileAsiaFirestoreCleanupJobs,
  reconcileNorthAmericaFirestoreCleanupJobs,
  reconcileEuropeFirestoreCleanupJobs,
  reconcileAsiaStorageCleanupJobs,
  reconcileNorthAmericaStorageCleanupJobs,
  reconcileEuropeStorageCleanupJobs,
} from "./cleanupTriggers";
export {
  processAsiaNotificationOutbox,
  processNorthAmericaNotificationOutbox,
  processEuropeNotificationOutbox,
  reconcileAsiaNotificationOutbox,
  reconcileNorthAmericaNotificationOutbox,
  reconcileEuropeNotificationOutbox,
} from "./notificationOutboxTriggers";

// Map exploration pin summaries and detail-entry proximity checks.
export {listMapPins, validateNoteAccess} from "./mapPins";

// Footprint visitor tracking.
export {recordNoteVisit, setFootprintEnabled} from "./visitors";

// Note likes.
export {setNoteLike} from "./likes";

// User following and blocking.
export {setUserBlock, setUserFollow} from "./social";

// Note lifecycle and metadata functions. Region set in their own options.
export {
  createNote,
  reportNote,
  setNotePinImage,
  setNoteTheme,
  archiveNote,
  archiveExpiredNotes,
}
  from "./notes";
