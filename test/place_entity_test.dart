import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/place_entity.dart';

void main() {
  group('PlaceEntity', () {
    test('treats creator and ownerIds as owners', () {
      final now = DateTime.now();
      final place = PlaceEntity(
        id: 'place-1',
        latitude: 35.6812,
        longitude: 139.7671,
        geohash: 'xn76u',
        title: 'Tokyo Station',
        colorHex: '#4CAF50',
        icon: 'place',
        createdByUserId: 'creator-1',
        ownerIds: const ['creator-1', 'owner-2'],
        createdAt: now,
        publishAt: now,
        expiresAt: now.add(const Duration(days: 7)),
      );

      expect(place.isOwnedBy('creator-1'), isTrue);
      expect(place.isOwnedBy('owner-2'), isTrue);
      expect(place.isOwnedBy('member-3'), isFalse);
      expect(place.isOwnedBy(null), isFalse);
    });
  });
}
