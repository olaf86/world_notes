import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/pin_summary_entity.dart';
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
      MaterialApp(
        home: Scaffold(
          body: NoteMarkerBottomSheet(pin: pin, onOpen: (_) async => true),
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
      MaterialApp(
        home: Scaffold(
          body: NoteMarkerBottomSheet(pin: pin, onOpen: (_) async => true),
        ),
      ),
    );

    expect(find.text('New from someone you follow'), findsOneWidget);
    expect(find.text('New messages'), findsOneWidget);
  });
}
