import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:world_notes/config/router.dart';
import 'package:world_notes/domain/entities/notice_entity.dart';
import 'package:world_notes/domain/entities/place_entity.dart';
import 'package:world_notes/domain/entities/user_entity.dart';
import 'package:world_notes/l10n/app_localizations.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/services/location_service.dart';

void main() {
  testWidgets(
    'opaque full-screen route offstages the shell and restores it on pop',
    (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream<UserEntity?>.value(
              const UserEntity(id: 'user-1', name: 'Test user'),
            ),
          ),
          isPremiumProvider.overrideWith((ref) => Stream.value(true)),
          noticesProvider.overrideWith(
            (ref) => Stream<List<NoticeEntity>>.value(const []),
          ),
          positionStreamProvider.overrideWith(
            (ref) => Stream<Position>.error(
              const LocationPermissionDeniedException(),
            ),
          ),
          placeProvider.overrideWith(
            (ref, placeId) => const Stream<PlaceEntity?>.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authStateProvider.future);
      await container.read(isPremiumProvider.future);
      final router = container.read(routerProvider);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);

      unawaited(router.push<void>('/note/place-1?title=Nearby%20note'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Nearby note'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationBar, skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);

      router.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
