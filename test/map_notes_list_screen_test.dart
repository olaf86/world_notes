import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:world_notes/domain/entities/pin_summary_entity.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/presentation/screens/map/map_notes_list_screen.dart';

void main() {
  testWidgets('shows access and followed-author indicators for each map note', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 13, 12);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          positionStreamProvider.overrideWith(
            (ref) => Stream.value(_position()),
          ),
          mapPinsProvider.overrideWith(
            (ref, request) async => [
              _pin(
                placeId: 'open-followed',
                now: now,
                access: PinAccess.openable,
                markerFlags: const {PinMarkerFlag.followedAuthorNew},
              ),
              _pin(
                placeId: 'locked',
                now: now,
                access: PinAccess.distanceLocked,
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: MapNotesListScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('From someone you follow'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Within access range. You can open this note.'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Outside access range. Move closer to open this note.',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('From a followed author.'), findsOneWidget);
    semantics.dispose();
  });
}

Position _position() => Position(
  latitude: 35,
  longitude: 139,
  timestamp: DateTime(2026, 7, 13, 12),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

PinSummary _pin({
  required String placeId,
  required DateTime now,
  required PinAccess access,
  Set<PinMarkerFlag> markerFlags = const {},
}) => PinSummary(
  placeId: placeId,
  latitude: 35,
  longitude: 139,
  title: 'Note $placeId',
  colorHex: '#4CAF50',
  icon: 'place',
  creatorName: 'Alice',
  messageCount: 0,
  likeCount: 0,
  visitorCount: 0,
  createdAt: now,
  lastActivityAt: now,
  expiresAt: now.add(const Duration(days: 7)),
  isPrivate: false,
  isClosed: false,
  footprintEnabled: true,
  access: access,
  markerFlags: markerFlags,
);
