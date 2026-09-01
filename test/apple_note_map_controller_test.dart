import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/pin_summary_entity.dart';
import 'package:world_notes/presentation/screens/map/apple_note_map_controller.dart';

void main() {
  testWidgets('publishes Apple pin positions before custom icons are ready', (
    tester,
  ) async {
    final controller = AppleNoteMapController(
      onPinSelected: (_) async {},
      onResolveMarkerImage: (_) async => null,
    );
    final pins = [_pin('a', 35.68), _pin('b', 35.69)];

    unawaited(controller.updateMarkers(pins));

    expect(controller.annotations.value, hasLength(2));
    expect(
      controller.annotations.value.map(
        (annotation) => annotation.annotationId.value,
      ),
      containsAll(<String>['single-a', 'single-b']),
    );

    controller.dispose();
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
