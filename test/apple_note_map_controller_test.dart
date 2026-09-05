import 'dart:async';
import 'dart:typed_data';

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

  testWidgets('keeps the placeholder until the final photo marker is ready', (
    tester,
  ) async {
    final imageRequested = Completer<void>();
    final markerImage = Completer<Uint8List?>();
    final controller = AppleNoteMapController(
      onPinSelected: (_) async {},
      onResolveMarkerImage: (_) {
        imageRequested.complete();
        return markerImage.future;
      },
    );
    addTearDown(controller.dispose);
    var annotationPublications = 0;
    controller.annotations.addListener(() => annotationPublications += 1);

    await tester.runAsync(() async {
      final update = controller.updateMarkers([
        _pin('photo', 35.68, pinImageStoragePath: 'pins/photo.jpg'),
      ]);
      await imageRequested.future;

      expect(annotationPublications, 1);

      markerImage.complete(null);
      await update;
      expect(annotationPublications, 2);
    });
  });
}

PinSummary _pin(String id, double latitude, {String? pinImageStoragePath}) {
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
    pinImageStoragePath: pinImageStoragePath,
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
