enum NearbyNotificationState {
  active,
  archived,
  revoked;

  static NearbyNotificationState fromJson(String? value) => switch (value) {
    'archived' => archived,
    'revoked' => revoked,
    _ => active,
  };
}

class NearbyNotificationPlace {
  final String placeId;
  final String title;
  final double latitude;
  final double longitude;
  final int radiusMeters;
  final DateTime expiresAt;
  final bool enabled;
  final NearbyNotificationState state;
  final DateTime? lastReadMessageAt;
  final DateTime? lastNotifiedMessageAt;

  /// Whether the device most recently reported being inside this note's
  /// notification radius.
  final bool inRange;

  /// Server-side expiry for the reported in-range state. While this is in the
  /// future, new messages can trigger nearby FCM without waiting for another
  /// geofence enter event. It also prevents stale "inside the area" state when
  /// an exit event is missed.
  final DateTime? inRangeUntil;
  final DateTime? updatedAt;

  const NearbyNotificationPlace({
    required this.placeId,
    required this.title,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.expiresAt,
    required this.enabled,
    required this.state,
    this.lastReadMessageAt,
    this.lastNotifiedMessageAt,
    this.inRange = false,
    this.inRangeUntil,
    this.updatedAt,
  });

  bool get isActive => enabled && state == NearbyNotificationState.active;
}

class NearbyUnreadResult {
  final bool hasUnread;
  final String? placeId;
  final String? messageId;
  final String? title;

  const NearbyUnreadResult({
    required this.hasUnread,
    this.placeId,
    this.messageId,
    this.title,
  });
}
