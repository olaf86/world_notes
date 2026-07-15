import '../entities/place_entity.dart';
import '../entities/message_entity.dart';

enum NoteRole { creator, maintainer, member, visitor, signedOut }

class NotePermissions {
  final NoteRole role;
  final bool canReadContent;
  final bool canPostMessage;
  final bool canLikeMessages;
  final bool canLikeNote;
  final bool canCloseThread;
  final bool canReopenThread;
  final bool canManageAccess;
  final bool canCreateInviteLink;
  final bool canRevokeInviteLink;
  final bool canRemoveMemberAccess;
  final bool canPromoteMaintainers;
  final bool canDemoteMaintainers;
  final bool canChangeLock;
  final bool canChangeTheme;
  final bool canArchive;

  const NotePermissions({
    required this.role,
    required this.canReadContent,
    required this.canPostMessage,
    required this.canLikeMessages,
    required this.canLikeNote,
    required this.canCloseThread,
    required this.canReopenThread,
    required this.canManageAccess,
    required this.canCreateInviteLink,
    required this.canRevokeInviteLink,
    required this.canRemoveMemberAccess,
    required this.canPromoteMaintainers,
    required this.canDemoteMaintainers,
    required this.canChangeLock,
    required this.canChangeTheme,
    required this.canArchive,
  });

  bool get isCreator => role == NoteRole.creator;
  bool get isMaintainer =>
      role == NoteRole.creator || role == NoteRole.maintainer;
  bool canLikeMessage(MessageEntity message, {required DateTime now}) =>
      canLikeMessages && message.isPublishedAt(now);
  bool get hasThreadActions =>
      canCloseThread ||
      canReopenThread ||
      canManageAccess ||
      canChangeLock ||
      canChangeTheme ||
      canArchive;
}

class NoteMemberPermissions {
  final bool canRemoveAccess;
  final bool canPromoteToMaintainer;
  final bool canDemoteMaintainer;

  const NoteMemberPermissions({
    required this.canRemoveAccess,
    required this.canPromoteToMaintainer,
    required this.canDemoteMaintainer,
  });

  bool get hasActions =>
      canRemoveAccess || canPromoteToMaintainer || canDemoteMaintainer;
}

extension NotePermissionPolicy on PlaceEntity {
  NoteRole roleFor({
    required String? uid,
    required NoteMembership? membership,
  }) {
    if (uid == null) return NoteRole.signedOut;
    if (uid == createdByUserId) return NoteRole.creator;
    if (maintainerIds.contains(uid)) return NoteRole.maintainer;
    if (isPrivate && isAccessibleBy(uid, membership)) return NoteRole.member;
    return NoteRole.visitor;
  }

  NotePermissions permissionsFor({
    required String? uid,
    required NoteMembership? membership,
    required bool readOnly,
    required DateTime now,
  }) {
    final role = roleFor(uid: uid, membership: membership);
    final hasUser = uid != null;
    final isCreator = role == NoteRole.creator;
    final isMaintainer =
        role == NoteRole.creator || role == NoteRole.maintainer;
    final canReadContent = isAccessibleBy(uid, membership);
    final canAcceptMessages = canAcceptMessagesAt(now);
    final canLikeMessages =
        hasUser &&
        canReadContent &&
        isPublishedAt(now) &&
        !isExpiredAt(now) &&
        !isArchived;

    return NotePermissions(
      role: role,
      canReadContent: canReadContent,
      canPostMessage:
          hasUser && canReadContent && !readOnly && canAcceptMessages,
      canLikeMessages: canLikeMessages,
      canLikeNote: canLikeMessages && !isCreator,
      canCloseThread: isMaintainer && !isArchived && isOpen,
      canReopenThread: isMaintainer && !isArchived && canReopen,
      canManageAccess: isMaintainer && !isArchived && isPrivate,
      canCreateInviteLink: isMaintainer && !isArchived && isPrivate,
      canRevokeInviteLink: isCreator && !isArchived && isPrivate,
      canRemoveMemberAccess: isMaintainer && !isArchived && isPrivate,
      canPromoteMaintainers: isCreator && !isArchived && isPrivate,
      canDemoteMaintainers: isCreator && !isArchived && isPrivate,
      canChangeLock: isCreator && !isArchived,
      canChangeTheme: isMaintainer && !isArchived,
      canArchive: isCreator && !isArchived,
    );
  }
}

extension NoteMemberPermissionPolicy on NoteMember {
  NoteMemberPermissions permissionsFor({
    required PlaceEntity place,
    required NotePermissions actor,
  }) {
    return NoteMemberPermissions(
      canRemoveAccess: actor.canRemoveMemberAccess && !isMaintainer,
      canPromoteToMaintainer: actor.canPromoteMaintainers && !isMaintainer,
      canDemoteMaintainer:
          actor.canDemoteMaintainers &&
          isMaintainer &&
          userId != place.createdByUserId,
    );
  }
}
