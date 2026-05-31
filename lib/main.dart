import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'config/router.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'services/subscription_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // App Check attests that requests come from a genuine, untampered build of
  // this app — the gate that makes the Phase 3 callable functions trustworthy.
  //   • iOS: App Attest on iOS 14+, falling back to DeviceCheck on iOS 11–13,
  //     so we keep the 13.0 deployment target without dropping older devices.
  //     App Attest needs a REAL device; the Simulator can't attest.
  //   • Debug builds use the debug provider — print the debug token from the
  //     console logs once and register it in Firebase Console → App Check.
  // NOTE: backend enforcement (enforceAppCheck) stays OFF until tokens are
  // confirmed flowing in the console's "unenforced" metrics, to avoid lockout.
  await FirebaseAppCheck.instance.activate(
    appleProvider: kDebugMode
        ? AppleProvider.debug
        : AppleProvider.appAttestWithDeviceCheckFallback,
    androidProvider:
        kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
  );

  await MobileAds.instance.initialize();
  await SubscriptionService.initialize();

  runApp(const ProviderScope(child: WorldNotesApp()));
}

class WorldNotesApp extends ConsumerWidget {
  const WorldNotesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
