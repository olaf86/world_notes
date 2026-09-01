import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:world_notes/domain/entities/pin_summary_entity.dart';
import 'package:world_notes/presentation/screens/map/google_note_map_controller.dart';

void main() {
  testWidgets('builds clustered Google markers for every pin', (tester) async {
    final controller = GoogleNoteMapController(
      onPinSelected: (_) async {},
      onResolveMarkerImage: (_) async => null,
    );
    unawaited(controller.updateMarkers([_pin('a', 35.68), _pin('b', 35.69)]));

    expect(controller.markers.value, hasLength(2));
    expect(
      controller.markers.value.map((marker) => marker.markerId.value),
      containsAll(<String>['a', 'b']),
    );
    expect(
      controller.markers.value.every(
        (marker) => marker.clusterManagerId?.value == 'world_notes_places',
      ),
      isTrue,
    );
    controller.dispose();
  });

  testWidgets('renders and hides the note access area', (tester) async {
    final controller = GoogleNoteMapController(
      onPinSelected: (_) async {},
      onResolveMarkerImage: (_) async => null,
    );
    addTearDown(controller.dispose);
    final position = Position(
      longitude: 139.76,
      latitude: 35.68,
      timestamp: DateTime(2026),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 1,
      heading: 0,
      headingAccuracy: 1,
      speed: 0,
      speedAccuracy: 1,
    );
    final colors = ColorScheme.fromSeed(seedColor: Colors.indigo);

    await controller.updateAccessArea(
      center: position,
      visible: true,
      radiusMeters: 500,
      colorScheme: colors,
    );

    expect(controller.accessAreaCircles.value, hasLength(1));
    expect(controller.accessAreaCircles.value.single.radius, 500);
    expect(
      controller.accessAreaCircles.value.single.center.latitude,
      position.latitude,
    );

    await controller.updateAccessArea(
      center: position,
      visible: false,
      radiusMeters: 500,
      colorScheme: colors,
    );
    expect(controller.accessAreaCircles.value, isEmpty);
  });
}

PinSummary _pin(String id, double latitude) {
  final now = DateTime(2026);
  return PinSummary(
    placeId: id,
    latitude: latitude,
    longitude: 139.76,
    title: 'Pin $id',
    colorHex: '#4CAF50',
    icon: 'place',
    creatorName: 'Alice',
    creatorPhotoVersion: 1,
    messageCount: 0,
    likeCount: 0,
    visitorCount: 0,
    createdAt: now,
    lastActivityAt: now,
    expiresAt: now.add(const Duration(days: 1)),
    isPrivate: false,
    isClosed: false,
    footprintEnabled: false,
    access: PinAccess.openable,
  );
}
