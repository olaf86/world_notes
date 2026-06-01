import '../../config/app_config.dart';

/// Axis 1 — Visibility (access control).
///
/// public  — any proximity user can read & write.
/// private — locked; access via password (verified server-side by a Cloud
///           Function) or by owner invitation.  Once granted, access persists
///           until the owner changes the password (tracked by passwordVersion).
enum PlaceVisibility {
  public,
  private;

  String toJson() => name;

  static PlaceVisibility fromJson(String? value) =>
      value == 'private' ? private : public;
}

/// Why a note thread was closed (read-only).
///
/// owner        — the owner closed it manually; the owner may re-open it.
/// messageLimit — the thread hit AppConfig.maxMessagesPerThread; it is full
///                and CANNOT be re-opened.
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
  final DateTime createdAt;
  final int messageCount;
  final DateTime? lastMessageAt;

  // ── Axis 1: Visibility ──────────────────────────────────────────────────
  final PlaceVisibility visibility;

  /// Increments each time the owner changes the password.  A remembered
  /// access grant is valid only while it matches the current version.
  /// The password hash itself is NOT stored here — it lives in a Cloud
  /// Function-protected location so clients can never read it.
  final int passwordVersion;

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
    required this.createdAt,
    required this.expiresAt,
    this.messageCount = 0,
    this.lastMessageAt,
    this.visibility = PlaceVisibility.public,
    this.passwordVersion = 0,
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

  /// Owner may re-open only notes they closed manually (never message-limit).
  bool get canReopen => isClosed && closedReason == ClosedReason.owner;

  /// Past its expiry but not yet archived by the server — the client treats
  /// these as effectively archived (filtered from search, read-only).
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Whether new messages may be posted right now.
  bool get canAcceptMessages =>
      isOpen && !isArchived && !isExpired && !isAtMessageLimit;

  /// Whether [uid] / [membership] may view this private note's content.
  /// Public notes are always accessible.
  bool isAccessibleBy(String? uid, NoteMembership? membership) {
    if (isPublic) return true;
    if (uid != null && uid == createdByUserId) return true;
    if (membership == null) return false;
    return membership.invited ||
        membership.viaPasswordVersion == passwordVersion;
  }
}

/// A user's access grant to a private note (places/{id}/members/{uid}).
class NoteMembership {
  /// Granted by an owner invitation (survives password changes).
  final bool invited;

  /// The note's passwordVersion at unlock time. Access is valid only while it
  /// still matches the note's current passwordVersion.
  final int viaPasswordVersion;

  const NoteMembership({
    required this.invited,
    required this.viaPasswordVersion,
  });
}

/// A member of a private note, as seen by the owner in the access list.
class NoteMember {
  final String userId;
  final String? displayName;
  final String? email;

  /// True for invite-link members; false for password-unlock members.
  final bool invited;

  const NoteMember({
    required this.userId,
    this.displayName,
    this.email,
    this.invited = false,
  });

  /// Best label to show for this member.
  String get label => displayName ?? email ?? userId;
}
