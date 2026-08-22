import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/place_entity.dart';
import 'package:world_notes/domain/policies/note_permissions.dart';

void main() {
  group('NotePermissionPolicy', () {
    final now = DateTime.utc(2026);

    PlaceEntity place({
      PlaceVisibility visibility = PlaceVisibility.private,
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
        creatorName: 'Creator',
        creatorPhotoVersion: 1,
        createdAt: now.subtract(const Duration(days: 1)),
        publishAt: now.subtract(const Duration(hours: 1)),
        expiresAt: now.add(const Duration(days: 1)),
        likeCount: 0,
        visibility: visibility,
        isOpen: isOpen,
        closedReason: closedReason,
        isArchived: isArchived,
        isModerationHidden: false,
      );
    }

    test('creator can perform creator-only and maintainer actions', () {
      final permissions = place().permissionsFor(
        uid: 'creator-1',
        membership: null,
        isAdministrator: false,
        readOnly: false,
        now: now,
      );

      expect(permissions.role, NoteRole.creator);
      expect(permissions.canReadContent, isTrue);
      expect(permissions.canPostMessage, isTrue);
      expect(permissions.canLikeNote, isFalse);
      expect(permissions.canManageAccess, isTrue);
      expect(permissions.canChangeLock, isTrue);
      expect(permissions.canArchive, isTrue);
    });

    test('maintainer can operate the thread but not creator-only actions', () {
      final permissions = place().permissionsFor(
        uid: 'maintainer-1',
        membership: null,
        isAdministrator: true,
        readOnly: false,
        now: now,
      );

      expect(permissions.role, NoteRole.maintainer);
      expect(permissions.canReadContent, isTrue);
      expect(permissions.canPostMessage, isTrue);
      expect(permissions.canLikeNote, isTrue);
      expect(permissions.canCloseThread, isTrue);
      expect(permissions.canManageAccess, isTrue);
      expect(permissions.canRemoveMemberAccess, isTrue);
      expect(permissions.canChangeLock, isFalse);
      expect(permissions.canArchive, isFalse);
    });

    test('private-note member can read and post but not manage', () {
      final permissions = place().permissionsFor(
        uid: 'member-1',
        membership: const NoteMembership(viaPasswordVersion: 0),
        isAdministrator: false,
        readOnly: false,
        now: now,
      );

      expect(permissions.role, NoteRole.member);
      expect(permissions.canReadContent, isTrue);
      expect(permissions.canPostMessage, isTrue);
      expect(permissions.canLikeNote, isTrue);
      expect(permissions.canManageAccess, isFalse);
      expect(permissions.canCloseThread, isFalse);
    });

    test('public signed-in viewer is a visitor, not a member', () {
      final permissions = place(visibility: PlaceVisibility.public)
          .permissionsFor(
            uid: 'visitor-1',
            membership: null,
            isAdministrator: false,
            readOnly: false,
            now: now,
          );

      expect(permissions.role, NoteRole.visitor);
      expect(permissions.canReadContent, isTrue);
      expect(permissions.canPostMessage, isTrue);
      expect(permissions.canLikeNote, isTrue);
      expect(permissions.canManageAccess, isFalse);
    });

    test('readOnly suppresses posting without suppressing management', () {
      final permissions = place().permissionsFor(
        uid: 'maintainer-1',
        membership: null,
        isAdministrator: true,
        readOnly: true,
        now: now,
      );

      expect(permissions.canPostMessage, isFalse);
      expect(permissions.canLikeNote, isTrue);
      expect(permissions.canCloseThread, isTrue);
      expect(permissions.canManageAccess, isTrue);
    });

    test('expired and archived notes cannot be liked', () {
      final expired = PlaceEntity(
        id: 'expired',
        latitude: 35.0,
        longitude: 139.0,
        geohash: 'xn76u',
        title: 'Expired note',
        colorHex: '#336699',
        icon: 'note',
        createdByUserId: 'creator-1',
        creatorName: 'Creator',
        creatorPhotoVersion: 1,
        createdAt: now.subtract(const Duration(days: 2)),
        publishAt: now.subtract(const Duration(days: 2)),
        expiresAt: now.subtract(const Duration(days: 1)),
        likeCount: 0,
        isModerationHidden: false,
      );
      final archived = place(isArchived: true);

      expect(
        expired
            .permissionsFor(
              uid: 'visitor-1',
              membership: null,
              isAdministrator: false,
              readOnly: false,
              now: now,
            )
            .canLikeNote,
        isFalse,
      );
      expect(
        archived
            .permissionsFor(
              uid: 'visitor-1',
              membership: null,
              isAdministrator: false,
              readOnly: false,
              now: now,
            )
            .canLikeNote,
        isFalse,
      );
    });
  });
}
