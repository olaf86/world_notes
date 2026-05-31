import '../entities/place_entity.dart';

abstract class PlaceRepository {
  Future<List<PlaceEntity>> getPlacesNearby({
    required double latitude,
    required double longitude,
  });

  Stream<List<PlaceEntity>> watchPlacesNearby({
    required double latitude,
    required double longitude,
  });

  Future<PlaceEntity> createPlace({
    required double latitude,
    required double longitude,
    required String title,
    String? subtitle,
    required String colorHex,
    required String icon,
    required String createdByUserId,
  });

  Future<PlaceEntity?> getPlace(String placeId);

  // ── Ownership queries ─────────────────────────────────────────────────────

  /// Returns the number of active (non-archived) notes owned by [userId].
  /// Used to enforce free / premium creation limits before writing to Firestore.
  Future<int> countUserActivePlaces(String userId);

  // ── Lifecycle management (owner only) ─────────────────────────────────────

  /// Closes the note thread — no new messages allowed, but the thread remains
  /// readable by proximity users.
  Future<void> closePlace(String placeId);

  /// Archives the note thread — moves it to cold-storage status.
  /// Future: content restricted; access requires owner approval.
  Future<void> archivePlace(String placeId);

  /// Re-opens a previously closed or archived place.
  Future<void> reopenPlace(String placeId);

  // ── Access control (owner only) ───────────────────────────────────────────

  /// Sets or clears the password lock on a note.
  ///
  /// Pass [isLocked] = true with a non-null [passwordHash] to lock the note.
  /// Pass [isLocked] = false (and null [passwordHash]) to unlock.
  ///
  /// [passwordHash] must be HMAC-SHA256 of the password keyed by the placeId,
  /// computed by [PasswordUtil.hash].  Never store plain-text passwords.
  Future<void> setPlaceLock({
    required String placeId,
    required bool isLocked,
    String? passwordHash,
  });
}
