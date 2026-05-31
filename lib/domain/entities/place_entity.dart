/// Lifecycle state of a note thread.
///
/// active   — open for new messages.
/// closed   — thread locked by the owner; existing messages are readable by
///            proximity users but no new messages can be posted.
/// archived — owner has archived the thread; content moves to cold storage
///            and access requires explicit owner approval (future feature).
enum PlaceStatus {
  active,
  closed,
  archived;

  String toJson() => name;

  static PlaceStatus fromJson(String? value) => switch (value) {
        'closed' => closed,
        'archived' => archived,
        _ => active, // default / unknown → treat as active
      };
}

class PlaceEntity {
  final String id;
  final double latitude;
  final double longitude;
  final String geohash;
  final String title;
  final String? subtitle;
  final String colorHex;
  final String icon;
  final String createdByUserId;
  final DateTime createdAt;
  final int messageCount;
  final DateTime? lastMessageAt;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  final PlaceStatus status;
  final DateTime? closedAt;
  final DateTime? archivedAt;

  // ── Access control ────────────────────────────────────────────────────────
  /// Whether this note is password-protected.
  final bool isLocked;

  /// HMAC-SHA256 of the password keyed by [id].
  /// Stored so the client can verify an entered password without transmitting
  /// it in plain text.  Never null when [isLocked] is true.
  final String? passwordHash;

  const PlaceEntity({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.geohash,
    required this.title,
    this.subtitle,
    required this.colorHex,
    required this.icon,
    required this.createdByUserId,
    required this.createdAt,
    this.messageCount = 0,
    this.lastMessageAt,
    this.status = PlaceStatus.active,
    this.closedAt,
    this.archivedAt,
    this.isLocked = false,
    this.passwordHash,
  });

  bool get isActive => status == PlaceStatus.active;
  bool get isClosed => status == PlaceStatus.closed;
  bool get isArchived => status == PlaceStatus.archived;
  bool get isAtMessageLimit => messageCount >= 1000;
}
