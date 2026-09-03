import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:world_notes/services/location_service.dart';

void main() {
  group('LocationService.ensurePermission', () {
    test('requests location permission when it is denied', () async {
      var permissionRequestCalls = 0;
      final service = LocationService(
        permissionChecker: () async => LocationPermission.denied,
        permissionRequester: () async {
          permissionRequestCalls += 1;
          return LocationPermission.whileInUse;
        },
      );

      final permission = await service.ensurePermission();

      expect(permission, LocationPermission.whileInUse);
      expect(permissionRequestCalls, 1);
    });

    test('does not request an existing location permission', () async {
      var permissionRequestCalls = 0;
      final service = LocationService(
        permissionChecker: () async => LocationPermission.whileInUse,
        permissionRequester: () async {
          permissionRequestCalls += 1;
          return LocationPermission.whileInUse;
        },
      );

      final permission = await service.ensurePermission();

      expect(permission, LocationPermission.whileInUse);
      expect(permissionRequestCalls, 0);
    });
  });

  group('locationAvailabilityIssueFromPermission', () {
    test('classifies unavailable permissions', () {
      expect(
        locationAvailabilityIssueFromPermission(LocationPermission.denied),
        LocationAvailabilityIssue.permissionDenied,
      );
      expect(
        locationAvailabilityIssueFromPermission(
          LocationPermission.deniedForever,
        ),
        LocationAvailabilityIssue.permissionPermanentlyDenied,
      );
      expect(
        locationAvailabilityIssueFromPermission(
          LocationPermission.unableToDetermine,
        ),
        LocationAvailabilityIssue.permissionDenied,
      );
    });

    test('allows granted permissions', () {
      expect(
        locationAvailabilityIssueFromPermission(LocationPermission.whileInUse),
        isNull,
      );
      expect(
        locationAvailabilityIssueFromPermission(LocationPermission.always),
        isNull,
      );
    });
  });

  group('locationAvailabilityIssueFromError', () {
    test('classifies location availability errors', () {
      expect(
        locationAvailabilityIssueFromError(
          const LocationPermissionDeniedException(),
        ),
        LocationAvailabilityIssue.permissionDenied,
      );
      expect(
        locationAvailabilityIssueFromError(
          const LocationPermissionDeniedException(permanentlyDenied: true),
        ),
        LocationAvailabilityIssue.permissionPermanentlyDenied,
      );
      expect(
        locationAvailabilityIssueFromError(
          const LocationServiceDisabledException(),
        ),
        LocationAvailabilityIssue.serviceDisabled,
      );
    });

    test('ignores unrelated errors', () {
      expect(locationAvailabilityIssueFromError(Exception('network')), isNull);
    });
  });
}
