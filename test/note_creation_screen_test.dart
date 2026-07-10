import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:world_notes/domain/entities/pin_summary_entity.dart';
import 'package:world_notes/domain/entities/place_entity.dart';
import 'package:world_notes/domain/entities/user_entity.dart';
import 'package:world_notes/domain/repositories/place_repository.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/presentation/screens/note/note_creation_screen.dart';
import 'package:world_notes/services/location_service.dart';

void main() {
  testWidgets('uses the current position when creating a note', (tester) async {
    final locationService = _FakeLocationService(
      position: _position(latitude: 35.681236, longitude: 139.767125),
    );
    final placeRepository = _RecordingPlaceRepository();

    await _pumpScreen(
      tester,
      locationService: locationService,
      placeRepository: placeRepository,
    );

    await tester.enterText(find.byType(TextFormField).first, 'Tokyo Station');
    await _scrollToCreateButton(tester);
    await tester.tap(find.text('Create Note'));
    await tester.pumpAndSettle();

    expect(locationService.getCurrentPositionCallCount, 1);
    expect(placeRepository.createNoteCallCount, 1);
    expect(placeRepository.latitude, 35.681236);
    expect(placeRepository.longitude, 139.767125);
  });

  testWidgets('uses archived note draft values when creating a fork', (
    tester,
  ) async {
    final locationService = _FakeLocationService(
      position: _position(latitude: 35.681236, longitude: 139.767125),
    );
    final placeRepository = _RecordingPlaceRepository();

    await _pumpScreen(
      tester,
      locationService: locationService,
      placeRepository: placeRepository,
      forkDraft: const NoteCreationDraft(
        latitude: 34.6937,
        longitude: 135.5023,
        title: 'Osaka Castle',
        subtitle: 'Stone walls and a wide moat',
        colorHex: '#2196F3',
        icon: 'star',
      ),
    );

    expect(find.text('Osaka Castle'), findsOneWidget);
    expect(find.text('Stone walls and a wide moat'), findsOneWidget);
    expect(
      find.text('This new note will use the archived note\'s location.'),
      findsOneWidget,
    );

    await _scrollToCreateButton(tester);
    await tester.tap(find.text('Create Note'));
    await tester.pumpAndSettle();

    expect(locationService.getCurrentPositionCallCount, 0);
    expect(placeRepository.createNoteCallCount, 1);
    expect(placeRepository.latitude, 34.6937);
    expect(placeRepository.longitude, 135.5023);
    expect(placeRepository.title, 'Osaka Castle');
    expect(placeRepository.subtitle, 'Stone walls and a wide moat');
  });

  testWidgets('does not create a note when current position fails', (
    tester,
  ) async {
    final locationService = _FakeLocationService(
      error: const LocationPermissionDeniedException(),
    );
    final placeRepository = _RecordingPlaceRepository();

    await _pumpScreen(
      tester,
      locationService: locationService,
      placeRepository: placeRepository,
    );

    await tester.enterText(find.byType(TextFormField).first, 'Tokyo Station');
    await _scrollToCreateButton(tester);
    await tester.tap(find.text('Create Note'));
    await tester.pump();

    expect(locationService.getCurrentPositionCallCount, 1);
    expect(placeRepository.createNoteCallCount, 0);
    expect(
      find.text('Location permission is required to create a note.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'offers settings when location permission is permanently denied',
    (tester) async {
      final locationService = _FakeLocationService(
        error: const LocationPermissionDeniedException(permanentlyDenied: true),
      );
      final placeRepository = _RecordingPlaceRepository();

      await _pumpScreen(
        tester,
        locationService: locationService,
        placeRepository: placeRepository,
      );

      await tester.enterText(find.byType(TextFormField).first, 'Tokyo Station');
      await _scrollToCreateButton(tester);
      await tester.tap(find.text('Create Note'));
      await tester.pump();
      await tester.pump();

      expect(locationService.getCurrentPositionCallCount, 1);
      expect(placeRepository.createNoteCallCount, 0);
      expect(find.text('Location permission needed'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
    },
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required LocationService locationService,
  required PlaceRepository placeRepository,
  NoteCreationDraft? forkDraft,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) {
          return Consumer(
            builder: (context, ref, child) {
              ref.watch(authStateProvider);
              return child!;
            },
            child: NoteCreationScreen(forkDraft: forkDraft),
          );
        },
      ),
      GoRoute(
        path: '/note/:placeId',
        builder: (context, state) => const SizedBox.shrink(),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => Stream.value(const UserEntity(id: 'user-1', name: 'Alice')),
        ),
        locationServiceProvider.overrideWithValue(locationService),
        placeRepositoryProvider.overrideWithValue(placeRepository),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollToCreateButton(WidgetTester tester) async {
  for (var i = 0; i < 8; i += 1) {
    if (find.text('Create Note').evaluate().isNotEmpty) return;
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
  }
}

Position _position({required double latitude, required double longitude}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime(2000),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

class _FakeLocationService extends LocationService {
  final Position? position;
  final Object? error;
  int getCurrentPositionCallCount = 0;

  _FakeLocationService({this.position, this.error});

  @override
  Future<Position> getCurrentPosition() async {
    getCurrentPositionCallCount += 1;
    final error = this.error;
    if (error != null) throw error;
    return position!;
  }
}

class _RecordingPlaceRepository implements PlaceRepository {
  int createNoteCallCount = 0;
  double? latitude;
  double? longitude;
  String? title;
  String? subtitle;

  @override
  Future<String> createNote({
    required double latitude,
    required double longitude,
    required String title,
    String? subtitle,
    required String colorHex,
    required String icon,
    required int expiryDays,
    DateTime? publishAt,
    PlaceVisibility visibility = PlaceVisibility.public,
    NoteLockDraft? lock,
  }) async {
    createNoteCallCount += 1;
    this.latitude = latitude;
    this.longitude = longitude;
    this.title = title;
    this.subtitle = subtitle;
    return 'place-1';
  }

  @override
  Future<List<PinSummary>> listMapPins({
    required double centerLatitude,
    required double centerLongitude,
    required double userLatitude,
    required double userLongitude,
    required double searchRadiusKm,
  }) async {
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
