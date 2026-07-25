import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:world_notes/domain/entities/pin_summary_entity.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/presentation/widgets/map/note_marker_bottom_sheet.dart';

void main() {
  testWidgets('shows the note creator name', (tester) async {
    final now = DateTime(2026, 6, 22, 12);
    final pin = PinSummary(
      placeId: 'place-1',
      latitude: 35,
      longitude: 139,
      title: 'A note',
      colorHex: '#4CAF50',
      icon: 'place',
      creatorName: 'Alice',
      creatorPhotoVersion: 1,
      messageCount: 0,
      likeCount: 0,
      visitorCount: 0,
      createdAt: now,
      lastActivityAt: now,
      expiresAt: now.add(const Duration(days: 7)),
      isPrivate: false,
      isClosed: false,
      footprintEnabled: true,
      access: PinAccess.openable,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: NoteMarkerBottomSheet(pin: pin, onOpen: (_) async => true),
          ),
        ),
      ),
    );

    expect(find.text('Alice'), findsOneWidget);
    expect(find.textContaining('Created at'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
  });

  testWidgets('shows followed-author and unseen-message states', (
    tester,
  ) async {
    final now = DateTime(2026, 6, 22, 12);
    final pin = PinSummary(
      placeId: 'place-1',
      latitude: 35,
      longitude: 139,
      title: 'A note',
      colorHex: '#4CAF50',
      icon: 'place',
      creatorName: 'Alice',
      creatorPhotoVersion: 1,
      messageCount: 2,
      likeCount: 0,
      visitorCount: 0,
      createdAt: now,
      lastActivityAt: now,
      expiresAt: now.add(const Duration(days: 7)),
      isPrivate: false,
      isClosed: false,
      footprintEnabled: true,
      access: PinAccess.openable,
      markerFlags: const {
        PinMarkerFlag.followedAuthorNew,
        PinMarkerFlag.unseenMessages,
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: NoteMarkerBottomSheet(pin: pin, onOpen: (_) async => true),
          ),
        ),
      ),
    );

    expect(find.text('New from someone you follow'), findsOneWidget);
    expect(find.text('New messages'), findsOneWidget);
  });

  testWidgets('updates the open action from the live position', (tester) async {
    final positions = StreamController<Position>();
    addTearDown(positions.close);
    PinSummary? openedPin;
    final pin = _pin(latitude: 35.005, access: PinAccess.distanceLocked);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          positionStreamProvider.overrideWith((ref) => positions.stream),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: NoteMarkerBottomSheet(
              pin: pin,
              onOpen: (value) async {
                openedPin = value;
                return false;
              },
            ),
          ),
        ),
      ),
    );

    positions.add(_position());
    await tester.pump();
    expect(find.text('Available nearby'), findsOneWidget);

    positions.add(_position(latitude: 35.001));
    await tester.pump();
    expect(find.text('Open Note'), findsOneWidget);

    await tester.tap(find.text('Open Note'));
    await tester.pump();
    expect(openedPin, same(pin));
    expect(openedPin?.access, PinAccess.distanceLocked);
  });
}

PinSummary _pin({double latitude = 35, PinAccess access = PinAccess.openable}) {
  final now = DateTime(2026, 6, 22, 12);
  return PinSummary(
    placeId: 'place-1',
    latitude: latitude,
    longitude: 139,
    title: 'A note',
    colorHex: '#4CAF50',
    icon: 'place',
    creatorName: 'Alice',
    creatorPhotoVersion: 1,
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
  );
}

Position _position({double latitude = 35}) => Position(
  latitude: latitude,
  longitude: 139,
  timestamp: DateTime(2026, 6, 22, 12),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);
