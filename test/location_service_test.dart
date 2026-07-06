import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:world_notes/services/location_service.dart';

void main() {
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
