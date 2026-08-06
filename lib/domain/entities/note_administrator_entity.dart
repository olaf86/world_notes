import '../../config/world_catalog.dart';

enum NoteAdministratorInvitationStatus {
  pending,
  accepted,
  revoked,
  expired;

  static NoteAdministratorInvitationStatus parse(Object? value) =>
      switch (value) {
        'pending' => pending,
        'accepted' => accepted,
        'revoked' => revoked,
        'expired' => expired,
        _ => throw const FormatException(
          'Administrator invitation status is invalid.',
        ),
      };
}

final class NoteAdministratorInvitationResult {
  const NoteAdministratorInvitationResult({
    required this.token,
    required this.placeId,
    required this.targetUid,
    required this.expiresAt,
  });

  final String token;
  final String placeId;
  final String targetUid;
  final DateTime expiresAt;
}

final class NoteAdministratorInvitationPreview {
  const NoteAdministratorInvitationPreview({
    required this.worldId,
    required this.placeId,
    required this.title,
    required this.invitedByUid,
    required this.status,
    required this.expiresAt,
    required this.worldReady,
    required this.canAccept,
  });

  final WorldId worldId;
  final String placeId;
  final String title;
  final String invitedByUid;
  final NoteAdministratorInvitationStatus status;
  final DateTime expiresAt;
  final bool worldReady;
  final bool canAccept;
}

final class NoteAdministrator {
  const NoteAdministrator({
    required this.userId,
    required this.isCreator,
    required this.displayName,
    required this.photoUrl,
    required this.invitedByUid,
    required this.grantedAt,
  });

  final String userId;
  final bool isCreator;
  final String? displayName;
  final String? photoUrl;
  final String? invitedByUid;
  final DateTime? grantedAt;

  String get label => displayName ?? userId;
}

final class PendingNoteAdministratorInvitation {
  const PendingNoteAdministratorInvitation({
    required this.targetUid,
    required this.invitedByUid,
    required this.displayName,
    required this.photoUrl,
    required this.revision,
    required this.expiresAt,
    required this.expired,
  });

  final String targetUid;
  final String invitedByUid;
  final String? displayName;
  final String? photoUrl;
  final int revision;
  final DateTime expiresAt;
  final bool expired;

  String get label => displayName ?? targetUid;
}

final class NoteAdministratorAccess {
  const NoteAdministratorAccess({
    required this.creatorUid,
    required this.administrators,
    required this.pendingInvitations,
  });

  final String creatorUid;
  final List<NoteAdministrator> administrators;
  final List<PendingNoteAdministratorInvitation> pendingInvitations;
}
