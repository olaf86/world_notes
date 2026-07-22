import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_config.dart';
import 'config/notification_navigation.dart';
import 'config/router.dart';
import 'config/runtime_mode.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'l10n/app_locale.dart';
import 'l10n/l10n.dart';
import 'presentation/providers/providers.dart';
import 'services/subscription_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await _configureFirebaseServices();
  await _signInScreenshotUserIfNeeded();

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

  if (AppConfig.supportsMobileAds) {
    await MobileAds.instance.initialize();
  }
  if (!screenshotMode) {
    await SubscriptionService.initialize();
  }

  final preferences = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: const WorldNotesApp(),
    ),
  );
}

Future<void> _configureFirebaseServices() async {
  if (shouldUseFirebaseEmulators) {
    final host = firebaseEmulatorHost();
    debugPrint('Using Firebase emulators (host: $host)');
    FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    FirebaseStorage.instance.useStorageEmulator(host, 9199);
    FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
    FirebaseFunctions.instanceFor(
      region: 'asia-northeast1',
    ).useFunctionsEmulator(host, 5001);
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
    return;
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
}

Future<void> _signInScreenshotUserIfNeeded() async {
  if (!shouldUseFirebaseEmulators || !screenshotMode) return;

  final auth = FirebaseAuth.instance;
  if (auth.currentUser != null) {
    await auth.signOut();
  }

  try {
    await auth.signInWithEmailAndPassword(
      email: screenshotAuthEmail,
      password: screenshotAuthPassword,
    );
    debugPrint('Signed in screenshot user: $screenshotAuthEmail');
  } on FirebaseAuthException catch (error) {
    if (error.code != 'user-not-found' && error.code != 'invalid-credential') {
      rethrow;
    }
    await auth.createUserWithEmailAndPassword(
      email: screenshotAuthEmail,
      password: screenshotAuthPassword,
    );
    await auth.currentUser?.updateDisplayName('World Notes Guide');
    debugPrint('Created screenshot user: $screenshotAuthEmail');
  }
}

class WorldNotesApp extends ConsumerStatefulWidget {
  const WorldNotesApp({super.key});

  @override
  ConsumerState<WorldNotesApp> createState() => _WorldNotesAppState();
}

class _WorldNotesAppState extends ConsumerState<WorldNotesApp> {
  StreamSubscription<NotificationPlaceRoute>? _notificationOpenSubscription;
  StreamSubscription<String>? _noticeOpenSubscription;

  @override
  void initState() {
    super.initState();
    if (screenshotMode) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = ref.read(myNotesNotificationServiceProvider);
      service.initialPlaceRouteFromLaunch().then(_openPlaceFromNotification);
      _notificationOpenSubscription = service.openedPlaceRoutes.listen(
        _openPlaceFromNotification,
      );
      final noticeService = ref.read(noticeNotificationServiceProvider);
      noticeService.initialNoticeIdFromLaunch().then(
        _openNoticesFromNotification,
      );
      _noticeOpenSubscription = noticeService.openedNoticeIds.listen(
        _openNoticesFromNotification,
      );
    });
  }

  @override
  void dispose() {
    _notificationOpenSubscription?.cancel();
    _noticeOpenSubscription?.cancel();
    super.dispose();
  }

  void _openPlaceFromNotification(NotificationPlaceRoute? route) {
    if (!mounted) return;
    openNotificationPlace(ref.read(routerProvider), route);
  }

  void _openNoticesFromNotification(String? noticeId) {
    if (!mounted || noticeId == null) return;
    openNotices(ref.read(routerProvider));
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final languagePreference = ref.watch(appLanguagePreferenceProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appName,
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
      localeListResolutionCallback: resolveAppLocale,
      locale: screenshotMode
          ? appLocaleFromTag(screenshotLocale)
          : languagePreference.locale,
    );
  }
}
