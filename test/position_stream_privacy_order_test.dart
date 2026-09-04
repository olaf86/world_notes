import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/services/ad_privacy_service.dart';
import 'package:world_notes/services/location_service.dart';

void main() {
  test(
    'starts location updates only after ad privacy setup completes',
    () async {
      final adPrivacyCompleter = Completer<AdPrivacyStatus>();
      final locationService = _RecordingLocationService();
      final container = ProviderContainer(
        overrides: [
          adPrivacyStatusProvider.overrideWith(
            (_) => adPrivacyCompleter.future,
          ),
          locationServiceProvider.overrideWithValue(locationService),
        ],
      );
      addTearDown(container.dispose);

      final firstPosition = container.read(positionStreamProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(locationService.watchStarted, isFalse);

      adPrivacyCompleter.complete(AdPrivacyStatus.disabled);

      expect(await firstPosition, _testPosition);
      expect(locationService.watchStarted, isTrue);
    },
  );
}

class _RecordingLocationService extends LocationService {
  bool watchStarted = false;

  @override
  Stream<Position> watchPosition() async* {
    watchStarted = true;
    yield _testPosition;
  }
}

final _testPosition = Position(
  latitude: 35.6812,
  longitude: 139.7671,
  timestamp: DateTime(2026),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);
