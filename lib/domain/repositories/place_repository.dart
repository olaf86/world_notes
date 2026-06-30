import '../entities/nearby_notification_entity.dart';
import '../entities/place_entity.dart';
import '../entities/pin_summary_entity.dart';

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
    required String icon,
    required int expiryDays,
    DateTime? publishAt,
    PlaceVisibility visibility = PlaceVisibility.public,
    NoteLockDraft? lock,
  });

  Future<PlaceEntity?> getPlace(String placeId);

  /// Live stream of a single place document. Emits null if it does not exist.
  Stream<PlaceEntity?> watchPlace(String placeId);

  // ── Ownership queries ─────────────────────────────────────────────────────

  /// Returns the number of active (non-archived) notes owned by [userId].
  /// Used to enforce free / premium creation limits before writing.
  Future<int> countUserActivePlaces(String userId);

  /// Active notes owned by [userId], used by the My Notes management view.
  Stream<List<PlaceEntity>> watchMyPlaces(String userId);
  Future<List<PlaceEntity>> getMyPlaces(String userId);

  /// Archived notes owned by [userId], used by the archived My Notes view.
  Stream<List<PlaceEntity>> watchArchivedMyPlaces(String userId);

  /// Permanently moves an active note to the archived lifecycle state.
  Future<void> archivePlace(String placeId);

  // ── Writability (owner only) ──────────────────────────────────────────────

  /// Closes the thread (read-only).  [reason] records whether this was a
  /// manual owner close or an automatic message-limit close.
  Future<void> closePlace(String placeId, {required ClosedReason reason});

  /// Re-opens a thread.  Only valid for owner-closed threads — the caller
  /// must verify [PlaceEntity.canReopen] first (rules also enforce this).
  Future<void> reopenPlace(String placeId);

  // ── Private access (Cloud Functions) ──────────────────────────────────────

  /// Owner-only: sets or changes the note's lock secret (locks it as private)
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

  // ── Invitations (Cloud Functions) ─────────────────────────────────────────

  /// Owner-only: returns the note's reusable invite token if one is already
  /// active. Does not create a new invite link.
  Future<String?> getInviteLink(String placeId);

  /// Owner-only: returns the note's reusable invite token (creating one if
  /// needed) via `createInviteLink`. Combine with [AppConfig.inviteLink].
  Future<String> createInviteLink(String placeId);

  /// Owner-only: revokes the note's invite link.
  Future<void> revokeInvite(String placeId);

  /// Owner-only: removes a single member's access grant.
  Future<void> revokeNoteAccess({
    required String placeId,
    required String userId,
  });

  /// Redeems an invite token for the signed-in user; returns the placeId to
  /// open. Throws [FirebaseFunctionsException] (`not-found` = invalid/revoked).
  Future<String> claimInvite(String token);

  /// Owner view of the note's access list (invited + password-unlock members).
  Stream<List<NoteMember>> watchMembers(String placeId);

  // ── Nearby notifications ─────────────────────────────────────────────────

  Stream<List<NearbyNotificationPlace>> watchNearbyNotificationPlaces(
    String userId,
  );

  Stream<NearbyNotificationPlace?> watchNearbyNotificationPlace({
    required String userId,
    required String placeId,
  });

  Future<void> setNearbyNotification({
    required String placeId,
    required bool enabled,
  });

  Future<void> markNearbyNotificationRead(String placeId);

  Future<void> markNearbyNotificationInRange({
    required String placeId,
    required bool inRange,
  });

  Future<NearbyUnreadResult> checkNearbyUnread(String placeId);
}
