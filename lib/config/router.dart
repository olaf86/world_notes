import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../presentation/providers/providers.dart';
import '../presentation/screens/auth/sign_in_screen.dart';
import '../presentation/screens/map/map_screen.dart';
import '../presentation/screens/note/note_box_screen.dart';
import '../presentation/screens/note/note_creation_screen.dart';
import '../presentation/screens/place/place_list_screen.dart';
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

      if (!isLoggedIn && !isAuthRoute) return '/auth/sign-in';
      if (isLoggedIn && isAuthRoute) return '/map';
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth/sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => _MainShell(child: child),
        routes: [
          GoRoute(
            path: '/map',
            builder: (context, state) => const MapScreen(),
          ),
          GoRoute(
            path: '/list',
            builder: (context, state) => const PlaceListScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/note/create',
        builder: (context, state) {
          final lat = double.tryParse(
                state.uri.queryParameters['lat'] ?? '',
              ) ??
              0;
          final lng = double.tryParse(
                state.uri.queryParameters['lng'] ?? '',
              ) ??
              0;
          return NoteCreationScreen(latitude: lat, longitude: lng);
        },
      ),
      GoRoute(
        path: '/note/:noteId',
        builder: (context, state) {
          final noteId = state.pathParameters['noteId']!;
          final placeTitle = state.uri.queryParameters['title'] ?? '';
          return NoteBoxScreen(noteId: noteId, placeTitle: placeTitle);
        },
      ),
      GoRoute(
        path: '/subscription',
        builder: (context, state) => const SubscriptionScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});

class _MainShell extends StatelessWidget {
  final Widget child;
  const _MainShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: _BottomNav(),
    );
  }
}

class _BottomNav extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = switch (true) {
      _ when location.startsWith('/list') => 1,
      _ when location.startsWith('/profile') => 2,
      _ => 0,
    };

    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) {
        if (index == 0) context.go('/map');
        if (index == 1) context.go('/list');
        if (index == 2) context.go('/profile');
      },
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
