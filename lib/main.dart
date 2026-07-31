import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/notification_navigation.dart';
import 'config/router.dart';
import 'config/runtime_mode.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'l10n/app_locale.dart';
import 'l10n/l10n.dart';
import 'presentation/providers/providers.dart';
import 'services/notice_notification_service.dart';
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

class _WorldNotesAppState extends ConsumerState<WorldNotesApp>
    with WidgetsBindingObserver {
  StreamSubscription<NotificationPlaceRoute>? _notificationOpenSubscription;
  StreamSubscription<NotificationNoticeRoute>? _noticeOpenSubscription;

  @override
  void initState() {
    super.initState();
    if (screenshotMode) return;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = ref.read(myNotesNotificationServiceProvider);
      service.initialPlaceRouteFromLaunch().then(_openPlaceFromNotification);
      _notificationOpenSubscription = service.openedPlaceRoutes.listen(
        _openPlaceFromNotification,
      );
      final noticeService = ref.read(noticeNotificationServiceProvider);
      noticeService.initialNoticeRouteFromLaunch().then(
        _openNoticesFromNotification,
      );
      _noticeOpenSubscription = noticeService.openedNoticeRoutes.listen(
        _openNoticesFromNotification,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationOpenSubscription?.cancel();
    _noticeOpenSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || screenshotMode) return;
    final privacyStatus = ref.read(adPrivacyStatusProvider);
    if (privacyStatus.hasError ||
        privacyStatus.valueOrNull?.shouldRetry == true) {
      ref.invalidate(adPrivacyStatusProvider);
    }
  }

  void _openPlaceFromNotification(NotificationPlaceRoute? route) {
    if (!mounted || route == null) return;
    try {
      ref.read(selectedWorldProvider.notifier).selectWorld(route.note.worldId);
    } on StateError {
      return;
    }
    openNotificationPlace(ref.read(routerProvider), route);
  }

  void _openNoticesFromNotification(NotificationNoticeRoute? route) {
    if (!mounted || route == null) return;
    try {
      ref
          .read(selectedWorldProvider.notifier)
          .selectWorld(route.notice.worldId);
    } on StateError {
      return;
    }
    openNotices(ref.read(routerProvider));
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final languagePreference = ref.watch(appLanguagePreferenceProvider);
    // Keep the post-login UMP/ATT flow alive for the app lifetime. Ad widgets
    // remain disabled until this provider allows requests and initializes the
    // Mobile Ads SDK.
    ref.watch(adPrivacyStatusProvider);

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
