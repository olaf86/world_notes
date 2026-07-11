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
export {sendMessage, deleteMessage, cancelScheduledMessage} from "./messages";
export {aggregatePublishedMessages} from "./messageTriggers";

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
  setNearbyNotification,
  markNearbyNotificationRead,
  markNearbyNotificationInRange,
  checkNearbyUnread,
} from "./notifications";

// User profile updates. Nickname changes keep future posts using the new name
// and refresh note access-list member labels.
export {updateDisplayName} from "./userProfile";

// Map exploration pin summaries and detail-entry proximity checks.
export {listMapPins, validateNoteAccess} from "./mapPins";

// Footprint visitor tracking.
export {recordNoteVisit, setFootprintEnabled} from "./visitors";

// Note likes.
export {setNoteLike} from "./likes";

// Note lifecycle and metadata functions. Region set in their own options.
export {createNote, setNotePinImage, archiveNote, archiveExpiredNotes}
  from "./notes";
