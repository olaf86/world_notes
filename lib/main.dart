import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'config/router.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'presentation/providers/providers.dart';
import 'services/subscription_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final crashlytics = FirebaseCrashlytics.instance;
  const collectCrashReports = !kDebugMode;
  await crashlytics.setCrashlyticsCollectionEnabled(collectCrashReports);
  if (collectCrashReports) {
    FlutterError.onError = crashlytics.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      crashlytics.recordError(error, stack, fatal: true);
      return true;
    };
  }

  // App Check attests that requests come from a genuine, untampered build of
  // this app — the gate that makes the Phase 3 callable functions trustworthy.
  //   • iOS: pure App Attest. The minimum deployment target is iOS 15 (forced
  //     by the Firebase iOS SDK anyway), which is >= App Attest's iOS 14
  //     floor, so no DeviceCheck fallback is needed. App Attest requires a
  //     REAL device; the Simulator can't attest.
  //   • Debug builds use the debug provider — print the debug token from the
  //     console logs once and register it in Firebase Console → App Check.
  await FirebaseAppCheck.instance.activate(
    providerApple: kDebugMode
        ? const AppleDebugProvider()
        : const AppleAppAttestProvider(),
    providerAndroid: kDebugMode
        ? const AndroidDebugProvider()
        : const AndroidPlayIntegrityProvider(),
  );

  await MobileAds.instance.initialize();
  await SubscriptionService.initialize();

  runApp(const ProviderScope(child: WorldNotesApp()));
}

class WorldNotesApp extends ConsumerStatefulWidget {
  const WorldNotesApp({super.key});

  @override
  ConsumerState<WorldNotesApp> createState() => _WorldNotesAppState();
}

class _WorldNotesAppState extends ConsumerState<WorldNotesApp> {
  StreamSubscription<String>? _notificationOpenSubscription;
  StreamSubscription<String>? _nearbyNotificationOpenSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = ref.read(myNotesNotificationServiceProvider);
      service.initialPlaceIdFromLaunch().then(_openPlaceFromNotification);
      _notificationOpenSubscription = service.openedPlaceIds.listen(
        _openPlaceFromNotification,
      );
      final nearbyService = ref.read(nearbyNotificationServiceProvider);
      nearbyService.initialize();
      nearbyService.initialPlaceIdFromLaunch().then(_openPlaceFromNotification);
      _nearbyNotificationOpenSubscription = nearbyService.openedPlaceIds.listen(
        _openPlaceFromNotification,
      );
      ref.read(nearbyProximityMonitorProvider);
    });
  }

  @override
  void dispose() {
    _notificationOpenSubscription?.cancel();
    _nearbyNotificationOpenSubscription?.cancel();
    super.dispose();
  }

  void _openPlaceFromNotification(String? placeId) {
    if (!mounted || placeId == null || placeId.isEmpty) return;
    ref.read(routerProvider).go(Uri(path: '/note/$placeId').toString());
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'World Notes',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
