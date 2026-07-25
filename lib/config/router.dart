import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/l10n.dart';
import '../domain/entities/content_report.dart';
import '../presentation/providers/providers.dart';
import '../presentation/screens/admin/admin_moderation_screen.dart';
import '../presentation/screens/auth/sign_in_screen.dart';
import '../presentation/screens/invite/invite_claim_screen.dart';
import '../presentation/screens/map/map_notes_screen.dart';
import '../presentation/screens/my_notes/my_notes_screen.dart';
import '../presentation/screens/note/note_box_screen.dart';
import '../presentation/screens/note/note_creation_screen.dart';
import '../presentation/screens/note/note_visitors_screen.dart';
import '../presentation/screens/notices/notices_screen.dart';
import '../presentation/screens/profile/follow_list_screen.dart';
import '../presentation/screens/profile/profile_screen.dart';
import '../presentation/screens/profile/user_profile_screen.dart';
import '../presentation/screens/report/report_message_screen.dart';
import '../presentation/screens/settings/settings_screen.dart';
import '../presentation/screens/subscription/subscription_screen.dart';
import 'route_observer.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/map',
    observers: [appRouteObserver],
    redirect: (context, state) {
      // While auth state is still resolving, don't redirect.
      if (authState.isLoading) return null;

      final isLoggedIn = authState.valueOrNull != null;
      final isAuthRoute = state.matchedLocation.startsWith('/auth');
      // Invite deep links are reachable while logged out so the claim screen
      // can prompt sign-in instead of bouncing to /map and losing the token.
      final isInviteRoute = state.matchedLocation.startsWith('/i/');

      if (!isLoggedIn && !isAuthRoute && !isInviteRoute) {
        return '/auth/sign-in';
      }
      if (isLoggedIn && isAuthRoute) return '/map';
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth/sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      // StatefulShellRoute keeps every branch mounted in an IndexedStack, so
      // switching tabs no longer disposes the previous screen. MapNotesScreen's
      // tracking toggle, anchor position, and MapLibre native camera state
      // (zoom / bearing / target) all survive a round-trip to other tabs.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/map',
                builder: (context, state) => const MapNotesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/my-notes',
                builder: (context, state) => const MyNotesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/notices',
                builder: (context, state) => const NoticesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      // Full-screen destinations are opaque. Once their transition completes,
      // Flutter can stop painting the shell (including the native map view)
      // underneath. _MainShell keeps its own layout finite while offstage, so
      // these pages don't need to remain transparent as a layout workaround.
      GoRoute(
        path: '/note/create',
        pageBuilder: (context, state) {
          final forkDraft = state.extra is NoteCreationDraft
              ? state.extra as NoteCreationDraft
              : null;
          return _fullScreenPage<void>(
            state: state,
            child: NoteCreationScreen(forkDraft: forkDraft),
          );
        },
      ),
      GoRoute(
        path: '/note/:placeId',
        pageBuilder: (context, state) {
          final placeId = state.pathParameters['placeId']!;
          final placeTitle = state.uri.queryParameters['title'] ?? '';
          final readOnly = state.uri.queryParameters['readOnly'] == 'true';
          final accessValidation = state.extra is NoteAccessValidationRequest
              ? state.extra as NoteAccessValidationRequest
              : null;
          return _fullScreenPage<void>(
            state: state,
            child: NoteBoxScreen(
              placeId: placeId,
              placeTitle: placeTitle,
              readOnly: readOnly,
              accessValidation: accessValidation,
            ),
          );
        },
      ),
      GoRoute(
        path: '/note/:placeId/messages/:messageId/report',
        pageBuilder: (context, state) {
          return _fullScreenPage<bool>(
            state: state,
            child: ReportContentScreen(
              placeId: state.pathParameters['placeId']!,
              messageId: state.pathParameters['messageId']!,
              target: ContentReportTarget.message,
            ),
          );
        },
      ),
      GoRoute(
        path: '/note/:placeId/report',
        pageBuilder: (context, state) {
          return _fullScreenPage<bool>(
            state: state,
            child: ReportContentScreen(
              placeId: state.pathParameters['placeId']!,
              target: ContentReportTarget.note,
            ),
          );
        },
      ),
      GoRoute(
        path: '/note/:placeId/visitors',
        pageBuilder: (context, state) {
          return _fullScreenPage<void>(
            state: state,
            child: NoteVisitorsScreen(
              placeId: state.pathParameters['placeId']!,
            ),
          );
        },
      ),
      GoRoute(
        path: '/users/:userId',
        pageBuilder: (context, state) => _fullScreenPage<void>(
          state: state,
          child: UserProfileScreen(userId: state.pathParameters['userId']!),
        ),
      ),
      GoRoute(
        path: '/users/:userId/followers',
        pageBuilder: (context, state) => _fullScreenPage<void>(
          state: state,
          child: FollowListScreen(
            userId: state.pathParameters['userId']!,
            followers: true,
          ),
        ),
      ),
      GoRoute(
        path: '/users/:userId/following',
        pageBuilder: (context, state) => _fullScreenPage<void>(
          state: state,
          child: FollowListScreen(
            userId: state.pathParameters['userId']!,
            followers: false,
          ),
        ),
      ),
      // Invite deep link: worldnotes.asobo.dev/i/{token}. Reachable logged out
      // (see redirect) so the claim screen can prompt sign-in.
      GoRoute(
        path: '/i/:token',
        pageBuilder: (context, state) => _fullScreenPage<void>(
          state: state,
          child: InviteClaimScreen(token: state.pathParameters['token']!),
        ),
      ),
      GoRoute(
        path: '/subscription',
        pageBuilder: (context, state) => _fullScreenPage<void>(
          state: state,
          child: const SubscriptionScreen(),
        ),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) =>
            _fullScreenPage<void>(state: state, child: const SettingsScreen()),
      ),
      GoRoute(
        path: '/admin/moderation',
        pageBuilder: (context, state) => _fullScreenPage<void>(
          state: state,
          child: const AdminModerationScreen(),
        ),
      ),
    ],
  );
});

class _MainShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const _MainShell({required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pin the position stream for the entire shell lifetime so tab switches
    // don't tear it down between MapScreen and MapNotesListScreen.
    ref.listen(positionStreamProvider, (_, _) {});

    // Keep the shell at an explicit finite size even when an opaque route puts
    // it offstage. Offstage lays its child out with the incoming constraints;
    // this boundary prevents an unconstrained overlay layout from propagating
    // into the IndexedStack, Scaffolds, or native map view.
    final size = MediaQuery.sizeOf(context);

    // A pushed route becomes current at the start of its transition. Pause
    // Flutter-driven map animations immediately and expose only the foreground
    // route to accessibility while the shell waits offstage. Riverpod state,
    // branch Navigators, and the native map widget remain mounted.
    final bool isCurrent = ModalRoute.of(context)?.isCurrent ?? true;

    return SizedBox(
      width: size.width,
      height: size.height,
      child: TickerMode(
        enabled: isCurrent,
        child: ExcludeSemantics(
          excluding: !isCurrent,
          child: Scaffold(
            body: navigationShell,
            bottomNavigationBar: _BottomNav(navigationShell: navigationShell),
          ),
        ),
      ),
    );
  }
}

class _BottomNav extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const _BottomNav({required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNoticeCountProvider);
    final l10n = context.l10n;
    return NavigationBar(
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: (index) => navigationShell.goBranch(
        index,
        // Tapping the already-selected tab pops that branch back to its
        // root, matching the iOS/Material navigation convention.
        initialLocation: index == navigationShell.currentIndex,
      ),
      destinations: [
        NavigationDestination(
          icon: Semantics(
            identifier: 'nav-map',
            child: const Icon(Icons.map_outlined),
          ),
          label: l10n.navMap,
        ),
        NavigationDestination(
          icon: Semantics(
            identifier: 'nav-notes',
            child: const Icon(Icons.bookmark_border_outlined),
          ),
          label: l10n.navNotes,
        ),
        NavigationDestination(
          icon: Semantics(
            identifier: 'nav-notifications',
            child: _NoticeNavIcon(count: unreadCount),
          ),
          selectedIcon: _NoticeNavIcon(count: unreadCount, selected: true),
          label: l10n.navNotifications,
        ),
        NavigationDestination(
          icon: Semantics(
            identifier: 'nav-profile',
            child: const Icon(Icons.person_outline),
          ),
          label: l10n.navProfile,
        ),
      ],
    );
  }
}

class _NoticeNavIcon extends StatelessWidget {
  final int count;
  final bool selected;

  const _NoticeNavIcon({required this.count, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Badge(
      isLabelVisible: count > 0,
      label: Text(count > 99 ? '99+' : '$count'),
      child: Icon(
        selected ? Icons.notifications : Icons.notifications_none_outlined,
        color: selected ? theme.colorScheme.primary : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared transition — right-to-left slide (standard push feel). Every page
// using this transition is opaque, allowing Flutter to stop painting routes
// underneath once the incoming page covers the screen.
// ---------------------------------------------------------------------------

CustomTransitionPage<T> _fullScreenPage<T>({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    opaque: true,
    transitionsBuilder: _slideTransition,
  );
}

Widget _slideTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  const begin = Offset(1.0, 0.0);
  const end = Offset.zero;
  final tween = Tween(
    begin: begin,
    end: end,
  ).chain(CurveTween(curve: Curves.easeInOut));
  return SlideTransition(position: animation.drive(tween), child: child);
}
