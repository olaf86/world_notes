import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/data/models/pin_summary_model.dart';

void main() {
  group('PinSummaryModel', () {
    final json = <String, dynamic>{
      'placeId': 'place-1',
      'latitude': 35.0,
      'longitude': 139.0,
      'title': 'A note',
      'subtitle': null,
      'colorHex': '#4CAF50',
      'themeId': 'aurora',
      'icon': 'place',
      'creatorName': 'Alice',
      'creatorPhotoVersion': 1,
      'messageCount': 2,
      'likeCount': 4,
      'visitorCount': 3,
      'createdAtMillis': 1000,
      'lastActivityAtMillis': 2000,
      'expiresAtMillis': 3000,
      'isPrivate': false,
      'isClosed': false,
      'footprintEnabled': true,
      'access': 'openable',
    };

    test('reads the creator name', () {
      final model = PinSummaryModel.fromJson({...json, 'creatorName': 'Alice'});

      expect(model.toEntity().creatorName, 'Alice');
    });

    test('reads an optional creator photo URL', () {
      final model = PinSummaryModel.fromJson({
        ...json,
        'creatorPhotoUrl': 'https://example.com/alice.png',
        'creatorPhotoVersion': 2,
      });

      expect(model.toEntity().creatorPhotoUrl, 'https://example.com/alice.png');
      expect(model.toEntity().creatorPhotoVersion, 2);
    });

    test('reads the like count', () {
      final model = PinSummaryModel.fromJson({...json, 'likeCount': 7});

      expect(model.toEntity().likeCount, 7);
    });

    test('reads an optional pin image storage path', () {
      final model = PinSummaryModel.fromJson({
        ...json,
        'pinImageStoragePath': 'images/pins/place-1.webp',
      });

      expect(model.toEntity().pinImageStoragePath, 'images/pins/place-1.webp');
    });

    test('reads the server-computed marker state', () {
      final model = PinSummaryModel.fromJson({
        ...json,
        'markerFlags': ['followedAuthorNew', 'unseenMessages'],
      });

      final pin = model.toEntity();
      expect(pin.isFromFollowedAuthor, isTrue);
      expect(pin.hasUnseenMessages, isTrue);
    });

    test('uses a normal marker when no marker flags are returned', () {
      final model = PinSummaryModel.fromJson(json);

      expect(model.toEntity().markerFlags, isEmpty);
    });

    test('rejects a missing theme id', () {
      expect(
        () => PinSummaryModel.fromJson(
          Map<String, dynamic>.from(json)..remove('themeId'),
        ),
        throwsArgumentError,
      );
    });
  });
}
