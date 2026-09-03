import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/pin_summary_entity.dart';
import 'package:world_notes/presentation/widgets/map/map_note_activity_badges.dart';

void main() {
  testWidgets('renders no badge for an ordinary note', (tester) async {
    await tester.pumpWidget(_app(_pin({})));

    expect(
      find.byKey(const ValueKey('map-note-activity-followed-author')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('map-note-activity-unseen')),
      findsNothing,
    );
  });

  testWidgets('renders independent followed-author and unseen states', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_pin({PinMarkerFlag.followedAuthorNew})));

    expect(
      find.byKey(const ValueKey('map-note-activity-followed-author')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('map-note-activity-unseen')),
      findsNothing,
    );

    await tester.pumpWidget(_app(_pin({PinMarkerFlag.unseenMessages})));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('map-note-activity-followed-author')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('map-note-activity-unseen')),
      findsOneWidget,
    );
    expect(find.text('New messages'), findsOneWidget);
    expect(find.textContaining('Last active'), findsOneWidget);
  });

  testWidgets('renders both states together', (tester) async {
    await tester.pumpWidget(
      _app(
        _pin({PinMarkerFlag.followedAuthorNew, PinMarkerFlag.unseenMessages}),
      ),
    );

    expect(
      find.byKey(const ValueKey('map-note-activity-unseen')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('map-note-activity-followed-author')),
      findsOneWidget,
    );
  });

  testWidgets('keeps the badge still when reduced motion is requested', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_pin({PinMarkerFlag.unseenMessages}), disableAnimations: true),
    );
    await tester.pump(const Duration(milliseconds: 450));

    expect(_badgeScale(tester), 1);
  });

  testWidgets('pulses the unseen badge when motion is allowed', (tester) async {
    await tester.pumpWidget(_app(_pin({PinMarkerFlag.unseenMessages})));
    await tester.pump(const Duration(milliseconds: 450));

    expect(_badgeScale(tester), greaterThan(1));
    await tester.pump(const Duration(milliseconds: 1350));
  });
}

Widget _app(PinSummary pin, {bool disableAnimations = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(body: MapNoteActivityBadges(pin: pin)),
  ),
);

double _badgeScale(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byKey(const ValueKey('map-note-activity-unseen')),
      matching: find.byType(Transform),
    ),
  );
  return transform.transform.getMaxScaleOnAxis();
}

PinSummary _pin(Set<PinMarkerFlag> markerFlags) {
  final now = DateTime.now();
  return PinSummary(
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
    createdAt: now.subtract(const Duration(days: 1)),
    lastActivityAt: now.subtract(const Duration(minutes: 5)),
    expiresAt: now.add(const Duration(days: 7)),
    isPrivate: false,
    isClosed: false,
    footprintEnabled: true,
    access: PinAccess.openable,
    markerFlags: markerFlags,
  );
}
