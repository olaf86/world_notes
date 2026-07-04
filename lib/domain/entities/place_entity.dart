import '../../config/app_config.dart';

/// Axis 1 — Visibility (access control).
///
/// public  — any proximity user can read & write.
/// private — locked; access via password/pattern (verified server-side by a
///           Cloud Function) or by maintainer invitation.  Once granted, access
///           persists until the creator changes the secret (tracked by
///           passwordVersion).
enum PlaceVisibility {
  public,
  private;

  String toJson() => name;

  static PlaceVisibility fromJson(String? value) =>
      value == 'private' ? private : public;
}

enum NoteLockType {
  password,
  pattern;

  String toJson() => name;

  static NoteLockType? fromJson(String? value) => switch (value) {
    'password' => password,
    'pattern' => pattern,
    _ => null,
  };
}

class NoteLockDraft {
  final NoteLockType lockType;
  final String secret;
  final String? lockHint;

  const NoteLockDraft({
    required this.lockType,
    required this.secret,
    this.lockHint,
  });
}

/// Why a note thread was closed (read-only).
///
/// owner        — a maintainer closed it manually; a maintainer may re-open it.
/// messageLimit — the thread hit AppConfig.maxMessagesPerThread; it is full
///                and CANNOT be manually re-opened.
enum ClosedReason {
  owner,
  messageLimit;

  String toJson() => name;

  static ClosedReason? fromJson(String? value) => switch (value) {
    'owner' => owner,
    'messageLimit' => messageLimit,
    _ => null,
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
  final List<String> maintainerIds;
  final DateTime createdAt;
  final DateTime publishAt;

  /// Publicly visible message count. Scheduled messages are counted only after
  /// they are published.
  final int messageCount;
  final DateTime? lastMessageAt;

  // ── Axis 1: Visibility ──────────────────────────────────────────────────
  final PlaceVisibility visibility;

  /// Increments each time the creator changes the lock secret.  A remembered
  /// access grant is valid only while it matches the current version.
  /// The password hash itself is NOT stored here — it lives in a Cloud
  /// Function-protected location so clients can never read it.
  final int passwordVersion;

  /// Public metadata for choosing the right unlock UI. Null means a legacy
  /// private note created before this field existed.
  final NoteLockType? lockType;

  /// Optional public hint shown on the locked view. The hint itself must not
  /// contain the full secret.
  final String? lockHint;

  // ── Axis 2: Writability ─────────────────────────────────────────────────
  /// true = open for new messages, false = closed (read-only).
  final bool isOpen;
  final ClosedReason? closedReason;
  final DateTime? closedAt;

  // ── Axis 3: Lifecycle ───────────────────────────────────────────────────
  /// Server-set (Cloud Function).  Archived notes are excluded from map/list
  /// search and moved to cold storage.  Terminal — no return to active.
  final bool isArchived;
  final DateTime? archivedAt;

  /// When the note auto-archives.  Required at creation, max 1 year out.
  /// The lifetime starts at publishAt, not createdAt, for scheduled notes.
  final DateTime expiresAt;

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
    this.maintainerIds = const [],
    required this.createdAt,
    required this.publishAt,
    required this.expiresAt,
    this.messageCount = 0,
    this.lastMessageAt,
    this.visibility = PlaceVisibility.public,
    this.passwordVersion = 0,
    this.lockType,
    this.lockHint,
    this.isOpen = true,
    this.closedReason,
    this.closedAt,
    this.isArchived = false,
    this.archivedAt,
  });

  // ── Convenience getters ─────────────────────────────────────────────────
  bool get isPublic => visibility == PlaceVisibility.public;
  bool get isPrivate => visibility == PlaceVisibility.private;
  bool get isClosed => !isOpen;
  bool get isAtMessageLimit => messageCount >= AppConfig.maxMessagesPerThread;

  /// Maintainers may re-open only notes closed manually (never message-limit).
  bool get canReopen => isClosed && closedReason == ClosedReason.owner;

  bool isMaintainedBy(String? uid) {
    if (uid == null) return false;
    return uid == createdByUserId || maintainerIds.contains(uid);
  }

  bool isPublishedAt(DateTime now) => !now.isBefore(publishAt);

  /// Past its expiry but not yet archived by the server — the client treats
  /// these as effectively archived (filtered from search, read-only).
  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  bool isDiscoverableAt(DateTime now) =>
      isPublishedAt(now) && !isExpiredAt(now) && !isArchived;

  /// Backward-compatible convenience for widgets that do not inject a clock.
  bool get isPublished => isPublishedAt(DateTime.now());
  bool get isExpired => isExpiredAt(DateTime.now());

  /// Whether new messages may be posted right now.
  bool canAcceptMessagesAt(DateTime now) =>
      isOpen && isDiscoverableAt(now) && !isAtMessageLimit;

  bool get canAcceptMessages => canAcceptMessagesAt(DateTime.now());

  /// Whether [uid] / [membership] may view this private note's content.
  /// Public notes are always accessible.
  bool isAccessibleBy(String? uid, NoteMembership? membership) {
    if (isPublic) return true;
    if (isMaintainedBy(uid)) return true;
    if (membership == null) return false;
    return membership.invited ||
        membership.viaPasswordVersion == passwordVersion;
  }
}

/// A user's access grant to a private note (places/{id}/members/{uid}).
class NoteMembership {
  /// Granted by a maintainer invitation (survives password changes).
  final bool invited;

  /// The note's passwordVersion at unlock time. Access is valid only while it
  /// still matches the note's current passwordVersion.
  final int viaPasswordVersion;

  const NoteMembership({
    required this.invited,
    required this.viaPasswordVersion,
  });
}

/// A member of a private note, as seen by maintainers in the access list.
class NoteMember {
  final String userId;
  final String? displayName;

  /// True for invite-link members; false for password-unlock members.
  final bool invited;

  /// True when this member is also listed in the note's maintainerIds.
  final bool isMaintainer;

  const NoteMember({
    required this.userId,
    this.displayName,
    this.invited = false,
    this.isMaintainer = false,
  });

  /// Best label to show for this member.
  String get label => displayName ?? userId;
}
