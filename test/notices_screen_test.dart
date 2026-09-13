import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:world_notes/domain/entities/notice_entity.dart';
import 'package:world_notes/domain/entities/user_entity.dart';
import 'package:world_notes/domain/repositories/notice_repository.dart';
import 'package:world_notes/l10n/app_localizations.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/presentation/screens/notices/notices_screen.dart';

void main() {
  testWidgets('localizes the empty notifications state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noticesProvider.overrideWith(
            (ref) => Stream<List<NoticeEntity>>.value(const []),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NoticesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('お知らせ'), findsOneWidget);
    expect(find.text('通知はまだありません。'), findsOneWidget);
    expect(find.text('No notifications yet.'), findsNothing);
  });

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
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
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

  testWidgets('requests that every unread notice be marked read', (
    tester,
  ) async {
    final repository = _PendingNoticeRepository();
    final notices = [
      NoticeEntity(
        id: 'unread-1',
        category: 'system',
        severity: 'info',
        title: 'First',
        body: 'First body',
        createdAt: DateTime(2026, 9, 13),
      ),
      NoticeEntity(
        id: 'already-read',
        category: 'system',
        severity: 'info',
        title: 'Second',
        body: 'Second body',
        createdAt: DateTime(2026, 9, 12),
        readAt: DateTime(2026, 9, 13),
      ),
      NoticeEntity(
        id: 'unread-2',
        category: 'mention',
        severity: 'info',
        title: 'Third',
        body: 'Third body',
        createdAt: DateTime(2026, 9, 11),
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream<UserEntity?>.value(
              const UserEntity(id: 'user-1', name: 'Test user'),
            ),
          ),
          noticesProvider.overrideWith(
            (ref) => Stream<List<NoticeEntity>>.value(notices),
          ),
          noticeRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          locale: const Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NoticesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mark-all-notices-read')));
    await tester.pumpAndSettle();

    expect(repository.markAllReadUserId, 'user-1');
    expect(repository.markAllReadCalls, 1);
  });
}

class _PendingNoticeRepository implements NoticeRepository {
  final _markRead = Completer<void>();
  int markReadCalls = 0;
  int markAllReadCalls = 0;
  String? markAllReadUserId;

  @override
  Future<void> markAllRead({required String userId}) async {
    markAllReadCalls += 1;
    markAllReadUserId = userId;
  }

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
