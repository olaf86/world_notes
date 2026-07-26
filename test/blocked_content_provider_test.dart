import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/note_visitor_entity.dart';
import 'package:world_notes/domain/repositories/place_repository.dart';
import 'package:world_notes/presentation/providers/providers.dart';

void main() {
  group('blocked content providers', () {
    late StreamController<Set<String>> blockedUsersController;
    late _VisitorPlaceRepository placeRepository;
    late ProviderContainer container;

    setUp(() {
      blockedUsersController = StreamController<Set<String>>();
      placeRepository = _VisitorPlaceRepository();
      container = ProviderContainer(
        overrides: [
          blockedUserIdsProvider.overrideWith(
            (ref) => blockedUsersController.stream,
          ),
          placeRepositoryProvider.overrideWithValue(placeRepository),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await blockedUsersController.close();
    });

    test('waits for block ids before exposing filtered visitors', () async {
      final provider = recentNoteVisitorsProvider('place-1');
      final filteredVisitors = Completer<List<NoteVisitor>>();
      final subscription = container.listen(provider, (_, state) {
        if (state.hasValue && !filteredVisitors.isCompleted) {
          filteredVisitors.complete(state.requireValue);
        }
      }, fireImmediately: true);
      addTearDown(subscription.close);

      expect(placeRepository.watchRecentVisitorsCallCount, 0);
      expect(container.read(provider).isLoading, isTrue);

      blockedUsersController.add({'blocked-user'});

      final visitors = await filteredVisitors.future;
      expect(placeRepository.watchRecentVisitorsCallCount, 1);
      expect(visitors.map((visitor) => visitor.userId), ['visible-user']);
    });

    test(
      'propagates a block-list failure instead of waiting forever',
      () async {
        final error = StateError('block list unavailable');
        final provider = recentNoteVisitorsProvider('place-1');
        final propagatedError = Completer<Object>();
        final subscription = container.listen(provider, (_, state) {
          final providerError = state.error;
          if (providerError != null && !propagatedError.isCompleted) {
            propagatedError.complete(providerError);
          }
        }, fireImmediately: true);
        addTearDown(subscription.close);

        blockedUsersController.addError(error);

        expect(await propagatedError.future, same(error));
        expect(placeRepository.watchRecentVisitorsCallCount, 0);
      },
    );
  });
}

class _VisitorPlaceRepository implements PlaceRepository {
  int watchRecentVisitorsCallCount = 0;

  @override
  Stream<List<NoteVisitor>> watchRecentVisitors({
    required String placeId,
    required int limit,
  }) {
    watchRecentVisitorsCallCount += 1;
    final now = DateTime(2026);
    return Stream.value([
      NoteVisitor(
        userId: 'blocked-user',
        firstVisitedAt: now,
        lastVisitedAt: now,
        visitCount: 1,
      ),
      NoteVisitor(
        userId: 'visible-user',
        firstVisitedAt: now,
        lastVisitedAt: now,
        visitCount: 1,
      ),
    ]);
  }

  @override
  // Test double shortcut: only watchRecentVisitors is exercised here.
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
