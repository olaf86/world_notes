import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/place_entity.dart';
import 'package:world_notes/domain/policies/note_permissions.dart';

void main() {
  group('NotePermissionPolicy', () {
    final now = DateTime.utc(2026);

    PlaceEntity place({
      PlaceVisibility visibility = PlaceVisibility.private,
      List<String> maintainerIds = const ['creator-1', 'maintainer-1'],
      bool isOpen = true,
      bool isArchived = false,
      ClosedReason? closedReason,
    }) {
      return PlaceEntity(
        id: 'place-1',
        latitude: 35.0,
        longitude: 139.0,
        geohash: 'xn76u',
        title: 'Test note',
        colorHex: '#336699',
        icon: 'note',
        createdByUserId: 'creator-1',
        maintainerIds: maintainerIds,
        createdAt: now.subtract(const Duration(days: 1)),
        publishAt: now.subtract(const Duration(hours: 1)),
        expiresAt: now.add(const Duration(days: 1)),
        visibility: visibility,
        isOpen: isOpen,
        closedReason: closedReason,
        isArchived: isArchived,
      );
    }

    test('creator can perform creator-only and maintainer actions', () {
      final permissions = place().permissionsFor(
        uid: 'creator-1',
        membership: null,
        readOnly: false,
        now: now,
      );

      expect(permissions.role, NoteRole.creator);
      expect(permissions.canReadContent, isTrue);
      expect(permissions.canPostMessage, isTrue);
      expect(permissions.canCreateInviteLink, isTrue);
      expect(permissions.canRevokeInviteLink, isTrue);
      expect(permissions.canPromoteMaintainers, isTrue);
      expect(permissions.canDemoteMaintainers, isTrue);
      expect(permissions.canChangeLock, isTrue);
      expect(permissions.canArchive, isTrue);
    });

    test('maintainer can operate the thread but not creator-only actions', () {
      final permissions = place().permissionsFor(
        uid: 'maintainer-1',
        membership: null,
        readOnly: false,
        now: now,
      );

      expect(permissions.role, NoteRole.maintainer);
      expect(permissions.canReadContent, isTrue);
      expect(permissions.canPostMessage, isTrue);
      expect(permissions.canCloseThread, isTrue);
      expect(permissions.canCreateInviteLink, isTrue);
      expect(permissions.canRemoveMemberAccess, isTrue);
      expect(permissions.canRevokeInviteLink, isFalse);
      expect(permissions.canPromoteMaintainers, isFalse);
      expect(permissions.canDemoteMaintainers, isFalse);
      expect(permissions.canChangeLock, isFalse);
      expect(permissions.canArchive, isFalse);
    });

    test('private-note member can read and post but not manage', () {
      final permissions = place().permissionsFor(
        uid: 'member-1',
        membership: const NoteMembership(invited: true, viaPasswordVersion: 0),
        readOnly: false,
        now: now,
      );

      expect(permissions.role, NoteRole.member);
      expect(permissions.canReadContent, isTrue);
      expect(permissions.canPostMessage, isTrue);
      expect(permissions.canManageAccess, isFalse);
      expect(permissions.canCreateInviteLink, isFalse);
      expect(permissions.canCloseThread, isFalse);
    });

    test('public signed-in viewer is a visitor, not a member', () {
      final permissions = place(visibility: PlaceVisibility.public)
          .permissionsFor(
            uid: 'visitor-1',
            membership: null,
            readOnly: false,
            now: now,
          );

      expect(permissions.role, NoteRole.visitor);
      expect(permissions.canReadContent, isTrue);
      expect(permissions.canPostMessage, isTrue);
      expect(permissions.canManageAccess, isFalse);
    });

    test('readOnly suppresses posting without suppressing management', () {
      final permissions = place().permissionsFor(
        uid: 'maintainer-1',
        membership: null,
        readOnly: true,
        now: now,
      );

      expect(permissions.canPostMessage, isFalse);
      expect(permissions.canCloseThread, isTrue);
      expect(permissions.canCreateInviteLink, isTrue);
    });

    test('member row actions follow actor permissions and target role', () {
      final privatePlace = place();
      final creator = privatePlace.permissionsFor(
        uid: 'creator-1',
        membership: null,
        readOnly: false,
        now: now,
      );
      final maintainer = privatePlace.permissionsFor(
        uid: 'maintainer-1',
        membership: null,
        readOnly: false,
        now: now,
      );
      const regularMember = NoteMember(userId: 'member-1', invited: true);
      const maintainerMember = NoteMember(
        userId: 'maintainer-1',
        invited: true,
        isMaintainer: true,
      );
      const creatorMember = NoteMember(
        userId: 'creator-1',
        invited: true,
        isMaintainer: true,
      );

      expect(
        regularMember
            .permissionsFor(place: privatePlace, actor: creator)
            .canPromoteToMaintainer,
        isTrue,
      );
      expect(
        maintainerMember
            .permissionsFor(place: privatePlace, actor: creator)
            .canDemoteMaintainer,
        isTrue,
      );
      expect(
        creatorMember
            .permissionsFor(place: privatePlace, actor: creator)
            .canDemoteMaintainer,
        isFalse,
      );
      expect(
        regularMember
            .permissionsFor(place: privatePlace, actor: maintainer)
            .canRemoveAccess,
        isTrue,
      );
      expect(
        regularMember
            .permissionsFor(place: privatePlace, actor: maintainer)
            .canPromoteToMaintainer,
        isFalse,
      );
    });
  });
}
