import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../presentation/providers/providers.dart';
import '../presentation/screens/auth/sign_in_screen.dart';
import '../presentation/screens/map/map_screen.dart';
import '../presentation/screens/note/message_creation_screen.dart';
import '../presentation/screens/note/note_box_screen.dart';
import '../presentation/screens/note/note_creation_screen.dart';
import '../presentation/screens/place/place_list_screen.dart';
import '../presentation/screens/profile/profile_screen.dart';
import '../presentation/screens/settings/settings_screen.dart';
import '../presentation/screens/subscription/subscription_screen.dart';

// Root Navigator key — used by the main shell and as the implicit parent for
// top-level routes.
final _rootNavigatorKey = GlobalKey<NavigatorState>();

// Note shell Navigator key — owns /note/:placeId and its child
// /note/:placeId/post.  Pushing the message creation screen onto THIS
// navigator (instead of the root navigator) keeps the offstage/Constraints
// chain contained to a small render subtree, avoiding the dry-baseline /
// '!semantics.parentDataDirty' cascade that occurs when complex routes are
// stacked on the root navigator.
final _noteShellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/map',
    redirect: (context, state) {
      // While auth state is still resolving, don't redirect.
      if (authState.isLoading) return null;

      final isLoggedIn = authState.valueOrNull != null;
      final isAuthRoute = state.matchedLocation.startsWith('/auth');

      if (!isLoggedIn && !isAuthRoute) return '/auth/sign-in';
      if (isLoggedIn && isAuthRoute) return '/map';
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth/sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      // StatefulShellRoute keeps every branch mounted in an IndexedStack, so
      // switching tabs no longer disposes the previous screen. MapScreen's
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
                builder: (context, state) => const MapScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/list',
                builder: (context, state) => const PlaceListScreen(),
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
          final lat = double.tryParse(
                state.uri.queryParameters['lat'] ?? '',
              ) ??
              0;
          final lng = double.tryParse(
                state.uri.queryParameters['lng'] ?? '',
              ) ??
              0;
          return CustomTransitionPage<void>(
            key: state.pageKey,
            child: NoteCreationScreen(latitude: lat, longitude: lng),
            opaque: false,
            transitionsBuilder: _slideTransition,
          );
        },
      ),
      // Note ShellRoute — owns /note/:placeId AND /note/:placeId/post in its
      // own Navigator (`_noteShellNavigatorKey`).  The post sub-route is
      // pushed onto this inner Navigator, so the route stack pops/pushes
      // happen against a small render subtree (just NoteBoxScreen) instead
      // of the entire app shell.  The outer shell + tabs stay untouched
      // beneath, exactly as before.
      ShellRoute(
        navigatorKey: _noteShellNavigatorKey,
        // The shell wrapper itself does not render any UI — its only job is
        // to host the inner Navigator.  The CustomTransitionPage applies the
        // right-to-left slide that we previously had on /note/:placeId.
        pageBuilder: (context, state, child) => CustomTransitionPage<void>(
          key: state.pageKey,
          child: child,
          opaque: false,
          transitionsBuilder: _slideTransition,
        ),
        routes: [
          GoRoute(
            path: '/note/:placeId',
            builder: (context, state) {
              final placeId = state.pathParameters['placeId']!;
              final placeTitle = state.uri.queryParameters['title'] ?? '';
              return NoteBoxScreen(
                placeId: placeId,
                placeTitle: placeTitle,
              );
            },
            routes: [
              // /note/:placeId/post — the new message creation screen.
              // Pushed inside the note shell with a bottom-to-top slide,
              // X / Twitter style.  opaque:false keeps NoteBoxScreen laid
              // out below so no Offstage wrapper is ever applied.
              GoRoute(
                path: 'post',
                pageBuilder: (context, state) {
                  final placeId = state.pathParameters['placeId']!;
                  return CustomTransitionPage<void>(
                    key: state.pageKey,
                    child: MessageCreationScreen(placeId: placeId),
                    opaque: false,
                    transitionsBuilder: _slideUpTransition,
                  );
                },
              ),
            ],
          ),
        ],
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
    // don't tear it down between MapScreen and PlaceListScreen.
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
      constraints: BoxConstraints(
        maxWidth: size.width,
        maxHeight: size.height,
      ),
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
          icon: Icon(Icons.list_alt_outlined),
          label: 'List',
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
  final tween = Tween(begin: begin, end: end)
      .chain(CurveTween(curve: Curves.easeInOut));
  return SlideTransition(position: animation.drive(tween), child: child);
}

// ---------------------------------------------------------------------------
// Slide-up transition — bottom-to-top, X / Twitter compose feel.
// Used by /note/:placeId/post.
// ---------------------------------------------------------------------------

Widget _slideUpTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  const begin = Offset(0.0, 1.0);
  const end = Offset.zero;
  final tween = Tween(begin: begin, end: end)
      .chain(CurveTween(curve: Curves.easeOutCubic));
  return SlideTransition(position: animation.drive(tween), child: child);
}
