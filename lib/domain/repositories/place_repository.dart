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
    required DateTime expiresAt,
    PlaceVisibility visibility,
  });

  Future<PlaceEntity?> getPlace(String placeId);

  /// Live stream of a single place document. Emits null if it does not exist.
  Stream<PlaceEntity?> watchPlace(String placeId);

  // ── Ownership queries ─────────────────────────────────────────────────────

  /// Returns the number of active (non-archived) notes owned by [userId].
  /// Used to enforce free / premium creation limits before writing.
  Future<int> countUserActivePlaces(String userId);

  // ── Writability (owner only) ──────────────────────────────────────────────

  /// Closes the thread (read-only).  [reason] records whether this was a
  /// manual owner close or an automatic message-limit close.
  Future<void> closePlace(String placeId, {required ClosedReason reason});

  /// Re-opens a thread.  Only valid for owner-closed threads — the caller
  /// must verify [PlaceEntity.canReopen] first (rules also enforce this).
  Future<void> reopenPlace(String placeId);
}
