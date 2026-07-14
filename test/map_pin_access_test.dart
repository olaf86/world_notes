import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:world_notes/domain/entities/pin_summary_entity.dart';
import 'package:world_notes/presentation/screens/map/map_pin_access.dart';

void main() {
  test('updates the server snapshot with the live distance-based access', () {
    final pin = _pin(access: PinAccess.distanceLocked);

    final accessible = pinWithLiveAccess(
      pin,
      position: _position(latitude: 35.001),
      accessRadiusMeters: 500,
    );
    final locked = pinWithLiveAccess(
      pin,
      position: _position(),
      accessRadiusMeters: 500,
    );

    expect(accessible.access, PinAccess.openable);
    expect(locked.access, PinAccess.distanceLocked);
  });
}

PinSummary _pin({required PinAccess access}) => PinSummary(
  placeId: 'place-1',
  latitude: 35.005,
  longitude: 139,
  title: 'Note',
  colorHex: '#4CAF50',
  icon: 'place',
  creatorName: 'Alice',
  messageCount: 0,
  likeCount: 0,
  visitorCount: 0,
  createdAt: DateTime(2026, 7, 14),
  lastActivityAt: DateTime(2026, 7, 14),
  expiresAt: DateTime(2026, 7, 21),
  isPrivate: false,
  isClosed: false,
  footprintEnabled: true,
  access: access,
);

Position _position({double latitude = 35, double longitude = 139}) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime(2026, 7, 14),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);
