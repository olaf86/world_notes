import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../presentation/providers/providers.dart';
import '../presentation/screens/auth/sign_in_screen.dart';
import '../presentation/screens/invite/invite_claim_screen.dart';
import '../presentation/screens/map/map_notes_screen.dart';
import '../presentation/screens/my_notes/my_notes_screen.dart';
import '../presentation/screens/note/note_box_screen.dart';
import '../presentation/screens/note/note_creation_screen.dart';
import '../presentation/screens/profile/profile_screen.dart';
import '../presentation/screens/settings/settings_screen.dart';
import '../presentation/screens/subscription/subscription_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/map',
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
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      // These routes are pushed on the root Navigator on top of the
      // StatefulShellRoute shell.  If they use the default opaque:true page,
      // Flutter's Navigator marks the shell route as offstage and wraps it in
      // Offstage(offstage:true), which passes BoxConstraints() (unbounded) to
      // the entire shell widget tree.  That triggers layout failures and the
      // cascading '!semantics.parentDataDirty' assertion loop.
      //
      // Fix: declare each route with opaque:false via CustomTransitionPage so
      // Flutter never marks the shell as offstage.  The shell continues to
      // receive proper screen-size constraints at all times.  NoteBoxScreen's
      // Scaffold surface colour hides the shell visually once the fade is
      // complete, so there is no perceptible difference to the user.
      GoRoute(
        path: '/note/create',
        pageBuilder: (context, state) {
          final lat =
              double.tryParse(state.uri.queryParameters['lat'] ?? '') ?? 0;
          final lng =
              double.tryParse(state.uri.queryParameters['lng'] ?? '') ?? 0;
          return CustomTransitionPage<void>(
            key: state.pageKey,
            child: NoteCreationScreen(latitude: lat, longitude: lng),
            opaque: false,
            transitionsBuilder: _slideTransition,
          );
        },
      ),
      GoRoute(
        path: '/note/:placeId',
        pageBuilder: (context, state) {
          final placeId = state.pathParameters['placeId']!;
          final placeTitle = state.uri.queryParameters['title'] ?? '';
          final readOnly = state.uri.queryParameters['readOnly'] == 'true';
          return CustomTransitionPage<void>(
            key: state.pageKey,
            child: NoteBoxScreen(
              placeId: placeId,
              placeTitle: placeTitle,
              readOnly: readOnly,
            ),
            opaque: false,
            transitionsBuilder: _slideTransition,
          );
        },
      ),
      // Invite deep link: worldnotes.asobo.dev/i/{token}. Reachable logged out
      // (see redirect) so the claim screen can prompt sign-in.
      GoRoute(
        path: '/i/:token',
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          child: InviteClaimScreen(token: state.pathParameters['token']!),
          opaque: false,
          transitionsBuilder: _slideTransition,
        ),
      ),
      GoRoute(
        path: '/subscription',
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          child: const SubscriptionScreen(),
          opaque: false,
          transitionsBuilder: _slideTransition,
        ),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          child: const SettingsScreen(),
          opaque: false,
          transitionsBuilder: _slideTransition,
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

    // LAYER 1 — Constraint clamp.
    //
    // StatefulShellRoute.indexedStack keeps all branches alive in an
    // IndexedStack.  Inactive branches are wrapped in Offstage(offstage:true).
    // Flutter's ModalRoute._ModalScope also wraps this shell in
    // Offstage(offstage:true) whenever an opaque route is pushed on top.
    //
    // In both cases Offstage passes BoxConstraints() — 0..∞ in every
    // dimension — to its child.  With unconstrained width/height, widgets
    // such as Column(crossAxisAlignment:.stretch), FilledButton.icon,
    // _ScrollableStatusView (SizedBox(height: constraints.maxHeight)), etc.
    // try to set a dimension to ∞, throw BoxConstraints.debugAssertIsValid,
    // and leave render objects in NEEDS-LAYOUT state.  The subsequent
    // semantics flush then hits those dirty nodes every frame and fires
    //   '!semantics.parentDataDirty': is not true
    // in an infinite loop.
    //
    // Fix: clamp incoming constraints to the actual screen size before they
    // reach any descendant.  MediaQuery.sizeOf is safe here because
    // _MainShell is always rebuilt whenever the window size changes.
    final size = MediaQuery.sizeOf(context);

    // LAYER 2 — Semantics exclusion.
    //
    // Even with clamped constraints, both the shell and the new route sit in
    // the semantics tree simultaneously while opaque:false routes are
    // animating in.  NavigationBar carries SemanticsRole.tabBar /
    // explicitChildNodes, which produces additional parentDataDirty noise
    // when two routes coexist.  Excluding the shell from semantics while it
    // is not the frontmost route removes that conflict entirely.
    final bool isCurrent = ModalRoute.of(context)?.isCurrent ?? true;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: size.width, maxHeight: size.height),
      child: ExcludeSemantics(
        excluding: !isCurrent,
        child: Scaffold(
          body: navigationShell,
          bottomNavigationBar: _BottomNav(navigationShell: navigationShell),
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const _BottomNav({required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: (index) => navigationShell.goBranch(
        index,
        // Tapping the already-selected tab pops that branch back to its
        // root, matching the iOS/Material navigation convention.
        initialLocation: index == navigationShell.currentIndex,
      ),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Map'),
        NavigationDestination(
          icon: Icon(Icons.bookmark_border_outlined),
          label: 'My Notes',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared transition — right-to-left slide (standard push feel).
// opaque:false is kept on all full-screen routes so the shell is never
// wrapped in Offstage(offstage:true), which would pass BoxConstraints()
// (0..∞) to the shell's children and trigger layout assertion loops.
// ---------------------------------------------------------------------------

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
