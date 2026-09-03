import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:world_notes/domain/entities/pin_summary_entity.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/presentation/screens/map/map_notes_list_screen.dart';
import 'package:world_notes/services/note_open_interstitial_service.dart';

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
                latitude: 35.01,
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: MapNotesListScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('New from someone you follow'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('map-note-activity-followed-author')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('note-list-card-highlight')),
      findsOneWidget,
    );
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

  testWidgets('does not make distance-locked notes tappable', (tester) async {
    final now = DateTime(2026, 7, 13, 12);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          positionStreamProvider.overrideWith(
            (ref) => Stream.value(_position()),
          ),
          mapPinsProvider.overrideWith(
            (ref, request) async => [
              _pin(
                placeId: 'locked',
                now: now,
                access: PinAccess.distanceLocked,
                latitude: 35.01,
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: MapNotesListScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    final noteCardInkWell = find.descendant(
      of: find.byType(Card),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(noteCardInkWell).onTap, isNull);
    await tester.tap(find.text('Note locked'));
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('opens an available note only once during rapid taps', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 13, 12);
    var navigationCount = 0;
    NoteAccessValidationRequest? accessRequest;
    final interstitialGate = _RecordingInterstitialGate();
    final router = GoRouter(
      initialLocation: '/list',
      routes: [
        GoRoute(path: '/list', builder: (_, _) => const MapNotesListScreen()),
        GoRoute(
          path: '/worlds/:worldId/notes/:placeId',
          builder: (_, state) {
            navigationCount += 1;
            accessRequest = state.extra as NoteAccessValidationRequest?;
            return Scaffold(
              body: Text('Opened ${state.pathParameters['placeId']}'),
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          positionStreamProvider.overrideWith(
            (ref) => Stream.value(_position()),
          ),
          mapPinsProvider.overrideWith(
            (ref, request) async => [
              _pin(placeId: 'open', now: now, access: PinAccess.openable),
            ],
          ),
          noteOpenInterstitialGateProvider.overrideWithValue(interstitialGate),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pump();
    await tester.pump();

    final note = find.text('Note open');
    await tester.tap(note);
    await tester.tap(note);
    await tester.tap(note);
    await tester.pumpAndSettle();

    expect(navigationCount, 1);
    expect(find.text('Opened open'), findsOneWidget);
    expect(accessRequest?.placeId, 'open');
    expect(accessRequest?.latitude, _position().latitude);
    expect(accessRequest?.longitude, _position().longitude);
    expect(interstitialGate.openedPlaceIds, ['open']);
  });

  testWidgets(
    'updates access and distance from live position without reloading pins',
    (tester) async {
      final now = DateTime(2026, 7, 13, 12);
      final positions = StreamController<Position>();
      addTearDown(positions.close);
      var mapPinsRequestCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            positionStreamProvider.overrideWith((ref) => positions.stream),
            mapPinsProvider.overrideWith((ref, request) async {
              mapPinsRequestCount += 1;
              return [
                _pin(
                  placeId: 'boundary',
                  now: now,
                  access: PinAccess.distanceLocked,
                  latitude: 35.005,
                ),
              ];
            }),
          ],
          child: const MaterialApp(home: MapNotesListScreen()),
        ),
      );

      positions.add(_position());
      await tester.pump();
      await tester.pump();

      expect(
        find.bySemanticsLabel(
          'Outside access range. Move closer to open this note.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          '${_distanceMeters(from: _position(), toLatitude: 35.005)} meters away',
        ),
        findsOneWidget,
      );
      expect(mapPinsRequestCount, 1);

      // This is only about 111m, below the 200m discovery-anchor threshold,
      // but crosses the 500m note-access boundary.
      positions.add(_position(latitude: 35.001));
      await tester.pump();

      expect(
        find.bySemanticsLabel('Within access range. You can open this note.'),
        findsOneWidget,
      );
      expect(
        find.text(
          '${_distanceMeters(from: _position(latitude: 35.001), toLatitude: 35.005)} meters away',
        ),
        findsOneWidget,
      );
      expect(mapPinsRequestCount, 1);
    },
  );

  testWidgets('keeps list order stable while live distances cross', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 13, 12);
    final positions = StreamController<Position>();
    addTearDown(positions.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          positionStreamProvider.overrideWith((ref) => positions.stream),
          mapPinsProvider.overrideWith(
            (ref, request) async => [
              _pin(
                placeId: 'north',
                now: now,
                access: PinAccess.openable,
                latitude: 35.001,
              ),
              _pin(
                placeId: 'south',
                now: now,
                access: PinAccess.openable,
                latitude: 34.9995,
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: MapNotesListScreen()),
      ),
    );

    positions.add(_position());
    await tester.pump();
    await tester.pump();

    final north = find.text('Note north');
    final south = find.text('Note south');
    expect(tester.getTopLeft(south).dy, lessThan(tester.getTopLeft(north).dy));

    // At this point north is nearer, but the 167m movement is below the
    // discovery-anchor threshold, so only the live display should update.
    positions.add(_position(latitude: 35.0015));
    await tester.pump();

    expect(tester.getTopLeft(south).dy, lessThan(tester.getTopLeft(north).dy));
  });
}

class _RecordingInterstitialGate implements NoteOpenInterstitialGate {
  final List<String> openedPlaceIds = [];

  @override
  Future<void> beforeNoteOpen({required String placeId}) async {
    openedPlaceIds.add(placeId);
  }
}

Position _position({double latitude = 35, double longitude = 139}) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime(2026, 7, 13, 12),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

int _distanceMeters({required Position from, required double toLatitude}) =>
    Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      toLatitude,
      139,
    ).round();

PinSummary _pin({
  required String placeId,
  required DateTime now,
  required PinAccess access,
  double latitude = 35,
  double longitude = 139,
  Set<PinMarkerFlag> markerFlags = const {},
}) => PinSummary(
  placeId: placeId,
  latitude: latitude,
  longitude: longitude,
  title: 'Note $placeId',
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
  markerFlags: markerFlags,
);
