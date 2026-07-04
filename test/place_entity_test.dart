import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/place_entity.dart';

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
        icon: 'place',
        createdByUserId: 'creator-1',
        maintainerIds: const ['creator-1', 'maintainer-2'],
        createdAt: now,
        publishAt: now,
        expiresAt: now.add(const Duration(days: 7)),
      );

      expect(place.isMaintainedBy('creator-1'), isTrue);
      expect(place.isMaintainedBy('maintainer-2'), isTrue);
      expect(place.isMaintainedBy('member-3'), isFalse);
      expect(place.isMaintainedBy(null), isFalse);
    });
  });
}
