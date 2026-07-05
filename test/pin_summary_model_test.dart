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
      'icon': 'place',
      'messageCount': 2,
      'createdAtMillis': 1000,
      'lastActivityAtMillis': 2000,
      'expiresAtMillis': 3000,
      'isPrivate': false,
      'isClosed': false,
      'access': 'openable',
    };

    test('reads the creator name', () {
      final model = PinSummaryModel.fromJson({...json, 'creatorName': 'Alice'});

      expect(model.toEntity().creatorName, 'Alice');
    });

    test('uses a safe fallback for legacy responses', () {
      final model = PinSummaryModel.fromJson(json);

      expect(model.toEntity().creatorName, 'Unknown user');
    });

    test('reads an optional pin image storage path', () {
      final model = PinSummaryModel.fromJson({
        ...json,
        'pinImageStoragePath': 'images/pins/place-1.webp',
      });

      expect(model.toEntity().pinImageStoragePath, 'images/pins/place-1.webp');
    });
  });
}
