import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/data/models/place_model.dart';
import 'package:world_notes/domain/entities/place_entity.dart';
import 'package:world_notes/domain/entities/note_theme.dart';

void main() {
  group('PlaceEntity', () {
    test('treats creator and maintainerIds as maintainers', () {
      final now = DateTime.now();
      final place = PlaceEntity(
        id: 'place-1',
        latitude: 35.6812,
        longitude: 139.7671,
        geohash: 'xn76u',
        title: 'Tokyo Station',
        colorHex: '#4CAF50',
        themeId: NoteThemeId.aurora,
        icon: 'place',
        createdByUserId: 'creator-1',
        creatorName: 'Alice',
        creatorPhotoVersion: 1,
        maintainerIds: const ['creator-1', 'maintainer-2'],
        createdAt: now,
        publishAt: now,
        expiresAt: now.add(const Duration(days: 7)),
        likeCount: 0,
        isModerationHidden: false,
      );

      expect(place.isMaintainedBy('creator-1'), isTrue);
      expect(place.isMaintainedBy('maintainer-2'), isTrue);
      expect(place.isMaintainedBy('member-3'), isFalse);
      expect(place.isMaintainedBy(null), isFalse);
    });

    test('carries an optional pin image storage path', () {
      final now = DateTime(2026, 7, 7, 12);
      final model = PlaceModel(
        id: 'place-1',
        latitude: 35.6812,
        longitude: 139.7671,
        geohash: 'xn76u',
        title: 'Tokyo Station',
        colorHex: '#4CAF50',
        themeId: NoteThemeId.aurora,
        icon: 'place',
        pinImageStoragePath: 'images/pins/place-1/user-1/thumb.webp',
        createdByUserId: 'creator-1',
        creatorName: 'Alice',
        creatorPhotoVersion: 1,
        createdAt: now,
        publishAt: now,
        expiresAt: now.add(const Duration(days: 7)),
        likeCount: 0,
        isModerationHidden: false,
      );

      expect(
        model.toEntity().pinImageStoragePath,
        'images/pins/place-1/user-1/thumb.webp',
      );
    });

    test('carries creator display details for list badges', () {
      final now = DateTime(2026, 7, 7, 12);
      final model = PlaceModel(
        id: 'place-1',
        latitude: 35.6812,
        longitude: 139.7671,
        geohash: 'xn76u',
        title: 'Tokyo Station',
        colorHex: '#4CAF50',
        themeId: NoteThemeId.aurora,
        icon: 'place',
        createdByUserId: 'creator-1',
        creatorName: 'Alice',
        creatorPhotoUrl: 'https://example.com/alice.png',
        creatorPhotoVersion: 2,
        createdAt: now,
        publishAt: now,
        expiresAt: now.add(const Duration(days: 7)),
        likeCount: 0,
        isModerationHidden: false,
      );

      final place = model.toEntity();
      expect(place.creatorName, 'Alice');
      expect(place.creatorPhotoUrl, 'https://example.com/alice.png');
      expect(place.creatorPhotoVersion, 2);
    });

    test('moderation-hidden notes are not discoverable or writable', () {
      final now = DateTime(2026, 7, 25, 12);
      final place = PlaceEntity(
        id: 'place-hidden',
        latitude: 35.6812,
        longitude: 139.7671,
        geohash: 'xn76u',
        title: 'Hidden note',
        colorHex: '#4CAF50',
        icon: 'place',
        createdByUserId: 'creator-1',
        creatorName: 'Alice',
        creatorPhotoVersion: 1,
        createdAt: now.subtract(const Duration(hours: 1)),
        publishAt: now.subtract(const Duration(hours: 1)),
        expiresAt: now.add(const Duration(days: 7)),
        likeCount: 0,
        isModerationHidden: true,
      );

      expect(place.isDiscoverableAt(now), isFalse);
      expect(place.canAcceptMessagesAt(now), isFalse);
    });
  });
}
