import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:world_notes/domain/entities/notice_entity.dart';
import 'package:world_notes/domain/entities/user_entity.dart';
import 'package:world_notes/domain/repositories/notice_repository.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/presentation/screens/notices/notices_screen.dart';

void main() {
  testWidgets('social notice navigates without waiting for mark-read write', (
    tester,
  ) async {
    final repository = _PendingNoticeRepository();
    final notice = NoticeEntity(
      id: 'notice-1',
      category: 'social',
      severity: 'info',
      title: 'New follower',
      body: 'Alice followed you.',
      createdAt: DateTime(2026, 7, 16),
      sourceId: 'alice',
    );
    final router = GoRouter(
      initialLocation: '/notices',
      routes: [
        GoRoute(
          path: '/notices',
          builder: (_, _) => Consumer(
            builder: (context, ref, child) {
              ref.watch(authStateProvider);
              return child!;
            },
            child: const NoticesScreen(),
          ),
        ),
        GoRoute(
          path: '/users/:userId',
          builder: (_, state) =>
              Scaffold(body: Text('Profile ${state.pathParameters['userId']}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream<UserEntity?>.value(
              const UserEntity(id: 'user-1', name: 'Test user'),
            ),
          ),
          noticesProvider.overrideWith(
            (ref) => Stream<List<NoticeEntity>>.value([notice]),
          ),
          noticeRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('New follower'));
    await tester.pumpAndSettle();

    expect(repository.markReadCalls, 1);
    expect(find.text('Profile alice'), findsOneWidget);
    repository.completeMarkRead();
  });
}

class _PendingNoticeRepository implements NoticeRepository {
  final _markRead = Completer<void>();
  int markReadCalls = 0;

  @override
  Future<void> markRead({required String userId, required String noticeId}) {
    markReadCalls += 1;
    return _markRead.future;
  }

  void completeMarkRead() => _markRead.complete();

  @override
  Stream<List<NoticeEntity>> watchNotices(String userId) =>
      const Stream.empty();
}
