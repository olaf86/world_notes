import '../entities/note_visitor_entity.dart';
import '../entities/note_list_sort.dart';
import '../entities/note_theme.dart';
import '../entities/place_entity.dart';
import '../entities/pin_summary_entity.dart';
import '../entities/content_report.dart';

abstract class PlaceRepository {
  Future<List<PinSummary>> listMapPins({
    required double centerLatitude,
    required double centerLongitude,
    required double userLatitude,
    required double userLongitude,
    required double searchRadiusKm,
  });

  Future<void> validateNoteAccess({
    required String placeId,
    required double latitude,
    required double longitude,
  });

  /// Creates a note via the `createNote` Cloud Function (the only path that
  /// may create a place — direct client writes are denied by rules). The
  /// function enforces the per-user note cap in a transaction and computes
  /// the geohash server-side. Returns the new place id.
  ///
  /// Throws [FirebaseFunctionsException] — callers should surface a clear
  /// message for `unavailable`/`deadline-exceeded` (offline) and
  /// `resource-exhausted` (note limit reached).
  Future<String> createNote({
    required double latitude,
    required double longitude,
    required String title,
    String? subtitle,
    required String colorHex,
    required NoteThemeId themeId,
    required String icon,
    required int expiryDays,
    DateTime? publishAt,
    PlaceVisibility visibility = PlaceVisibility.public,
    NoteLockDraft? lock,
  });

  /// Stores a map-pin thumbnail for an existing note and records its storage
  /// path server-side. Only the generated thumbnail is uploaded; the original
  /// image is not retained.
  Future<void> setNotePinImage({
    required String placeId,
    required String userId,
    required List<int> thumbnailBytes,
  });

  /// Submits a user report for a note maintained by another user.
  Future<void> reportNote({
    required String placeId,
    required ReportReasonCode reasonCode,
  });

  Future<PlaceEntity?> getPlace(String placeId);

  /// Live stream of a single place document. Emits null if it does not exist.
  Stream<PlaceEntity?> watchPlace(String placeId);

  // ── Maintainer queries ────────────────────────────────────────────────────

  /// Returns the number of active (non-archived) notes maintained by [userId].
  /// Used to enforce free / premium creation limits before writing.
  Future<int> countUserActivePlaces(String userId);

  /// Active notes maintained by [userId], used by the My Notes view.
  Stream<List<PlaceEntity>> watchMyPlaces(String userId);
  Future<List<PlaceEntity>> getMyPlaces(String userId);

  /// Returns the total number of archived notes maintained by [userId].
  Future<int> countArchivedMyPlaces(String userId);

  /// Returns one ordered page of archived notes maintained by [userId].
  Future<ArchivedPlacesPage> listArchivedMyPlaces({
    required String userId,
    required NoteListSort sort,
    Object? cursor,
    int limit = 50,
  });

  /// Permanently moves an active note to the archived lifecycle state.
  Future<void> archivePlace(String placeId);

  // ── Writability (maintainer only) ─────────────────────────────────────────

  /// Closes the thread (read-only).  [reason] records whether this was a
  /// manual maintainer close or an automatic message-limit close.
  Future<void> closePlace(String placeId, {required ClosedReason reason});

  /// Re-opens a thread.  Only valid for maintainer-closed threads — the caller
  /// must verify [PlaceEntity.canReopen] first (rules also enforce this).
  Future<void> reopenPlace(String placeId);

  /// Maintainer-only: changes the built-in visual theme of an active note.
  Future<void> setNoteTheme({
    required String placeId,
    required NoteThemeId themeId,
  });

  // ── Private access (Cloud Functions) ──────────────────────────────────────

  /// Creator-only: sets or changes the note's lock secret (locks it as private)
  /// via the `setNotePassword` function. Throws [FirebaseFunctionsException].
  Future<void> setNotePassword({
    required String placeId,
    required String password,
    required NoteLockType lockType,
    String? lockHint,
  });

  /// Verifies [password] via the `unlockNote` function; on success the server
  /// records this user's access grant. Throws [FirebaseFunctionsException]
  /// (`permission-denied` = wrong password, `resource-exhausted` = locked out).
  Future<void> unlockNote({required String placeId, required String password});

  /// Live stream of the current user's access grant to a private note
  /// (null when none). Used to decide whether to prompt for a password.
  Stream<NoteMembership?> watchMembership({
    required String placeId,
    required String userId,
  });

  // ── Likes (Cloud Functions + per-user Firestore state) ───────────────────

  /// Live stream of the current user's like state for a note.
  Stream<bool> watchNoteLike({required String placeId, required String userId});

  /// Sets the current user's final desired like state via `setNoteLike`.
  /// The function is idempotent: sending the already-stored state is a no-op.
  Future<void> setNoteLike({required String placeId, required bool liked});

  // ── Invitations (Cloud Functions) ─────────────────────────────────────────

  /// Maintainer-only: returns the note's reusable invite token if one is
  /// already active. Does not create a new invite link.
  Future<String?> getInviteLink(String placeId);

  /// Maintainer-only: returns the note's reusable invite token (creating one
  /// if needed) via `createInviteLink`. Combine with [AppConfig.inviteLink].
  Future<String> createInviteLink(String placeId);

  /// Creator-only: revokes the note's invite link.
  Future<void> revokeInvite(String placeId);

  /// Maintainer-only: removes a single regular member's access grant.
  Future<void> revokeNoteAccess({
    required String placeId,
    required String userId,
  });

  /// Creator-only: promotes an existing member to a maintainer.
  Future<void> grantNoteMaintainer({
    required String placeId,
    required String userId,
  });

  /// Creator-only: removes maintainer status from a member.
  Future<void> revokeNoteMaintainer({
    required String placeId,
    required String userId,
  });

  /// Redeems an invite token for the signed-in user; returns the placeId to
  /// open. Throws [FirebaseFunctionsException] (`not-found` = invalid/revoked).
  Future<String> claimInvite(String token);

  /// Maintainer view of the note's access list.
  Stream<List<NoteMember>> watchMembers(String placeId);

  // ── Footprints / visitors ────────────────────────────────────────────────

  /// Records that the current signed-in user opened this note. The server
  /// decides whether footprints are enabled and whether the user may access it.
  Future<void> recordNoteVisit(String placeId);

  /// Recent visitors for the compact note-detail preview.
  Stream<List<NoteVisitor>> watchRecentVisitors({
    required String placeId,
    required int limit,
  });

  /// Visitors for the dedicated visitor screen.
  Stream<List<NoteVisitor>> watchVisitors({
    required String placeId,
    required NoteVisitorSort sort,
  });

  /// Maintainer-only: controls whether this note records footprints.
  Future<void> setFootprintEnabled({
    required String placeId,
    required bool enabled,
  });
}
