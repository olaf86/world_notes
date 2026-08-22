import 'package:flutter/foundation.dart';

const bool useFirebaseEmulators = bool.fromEnvironment(
  'USE_FIREBASE_EMULATORS',
  defaultValue: false,
);

const bool screenshotMode = bool.fromEnvironment(
  'SCREENSHOT_MODE',
  defaultValue: false,
);

const bool _acceptanceTestModeRequested = bool.fromEnvironment(
  'ACCEPTANCE_TEST_MODE',
  defaultValue: false,
);

const String screenshotAuthEmail = String.fromEnvironment(
  'SCREENSHOT_AUTH_EMAIL',
  defaultValue: 'screenshot@example.com',
);

const String screenshotAuthPassword = String.fromEnvironment(
  'SCREENSHOT_AUTH_PASSWORD',
  defaultValue: 'Passw0rd!',
);

const String screenshotLocale = String.fromEnvironment(
  'SCREENSHOT_LOCALE',
  defaultValue: 'ja',
);

const String _screenshotLatitudeValue = String.fromEnvironment(
  'SCREENSHOT_LATITUDE',
  defaultValue: '35.6812',
);

const String _screenshotLongitudeValue = String.fromEnvironment(
  'SCREENSHOT_LONGITUDE',
  defaultValue: '139.7671',
);

double get screenshotLatitude =>
    double.tryParse(_screenshotLatitudeValue) ?? 35.6812;

double get screenshotLongitude =>
    double.tryParse(_screenshotLongitudeValue) ?? 139.7671;

bool get shouldUseFirebaseEmulators => useFirebaseEmulators && kDebugMode;

/// Whether acceptance-test isolation is active for this app process.
///
/// The compile-time request is honored only in debug emulator builds so the
/// isolation behavior cannot accidentally reach a production backend.
bool get acceptanceTestMode =>
    shouldUseFirebaseEmulators && _acceptanceTestModeRequested;

String firebaseEmulatorHost() {
  if (kIsWeb) return 'localhost';

  return switch (defaultTargetPlatform) {
    TargetPlatform.android => '10.0.2.2',
    TargetPlatform.iOS ||
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux ||
    TargetPlatform.fuchsia => 'localhost',
  };
}
