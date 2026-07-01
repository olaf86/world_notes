import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/pin_summary_entity.dart';
import 'package:world_notes/domain/entities/user_entity.dart';
import 'package:world_notes/domain/repositories/place_repository.dart';
import 'package:world_notes/presentation/providers/providers.dart';

void main() {
  group('mapPinsProvider', () {
    late StreamController<UserEntity?> authController;
    late _RecordingPlaceRepository placeRepository;
    late ProviderContainer container;

    setUp(() {
      authController = StreamController<UserEntity?>();
      placeRepository = _RecordingPlaceRepository();
      container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => authController.stream),
          placeRepositoryProvider.overrideWithValue(placeRepository),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await authController.close();
    });

    test('waits for auth restoration before loading pins', () async {
      final future = container.read(mapPinsProvider(_request).future);

      await Future<void>.delayed(Duration.zero);

      expect(placeRepository.listMapPinsCallCount, 0);

      authController.add(const UserEntity(id: 'user-1', name: 'User One'));

      await future;

      expect(placeRepository.listMapPinsCallCount, 1);
    });

    test('does not call the pin API while signed out', () async {
      final future = container.read(mapPinsProvider(_request).future);

      authController.add(null);

      await expectLater(future, completion(isEmpty));
      expect(placeRepository.listMapPinsCallCount, 0);
    });
  });
}

const _request = MapPinsRequest(
  center: MapLatLng(35, 139),
  user: MapLatLng(35, 139),
  radiusKm: 2,
);

class _RecordingPlaceRepository implements PlaceRepository {
  int listMapPinsCallCount = 0;

  @override
  Future<List<PinSummary>> listMapPins({
    required double centerLatitude,
    required double centerLongitude,
    required double userLatitude,
    required double userLongitude,
    required double searchRadiusKm,
  }) async {
    listMapPinsCallCount += 1;
    return const <PinSummary>[];
  }

  @override
  // Test double shortcut: only listMapPins is exercised here. If another
  // PlaceRepository member is called, Object.noSuchMethod throws.
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
