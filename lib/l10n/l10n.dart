import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart' show GlobalMaterialLocalizations;

import 'app_localizations.dart';

export 'app_localizations.dart';

/// Localization delegates compatible with the standalone Material and
/// Cupertino UI packages introduced in Flutter 3.50.
const appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

/// The single entry point for localized UI copy.
///
/// The fallback keeps small widget tests usable even when their test harness
/// does not register the app localization delegate.
extension AppLocalizationsBuildContext on BuildContext {
  AppLocalizations get l10n {
    return AppLocalizations.of(this) ??
        lookupAppLocalizations(Localizations.localeOf(this));
  }

  String get localeTag => Localizations.localeOf(this).toLanguageTag();
}

/// Localized display name for the PRO plan.
///
/// RevenueCat product identifiers stay language-independent, while every
/// user-facing plan label follows the localized app name.
extension AppLocalizationsProPlanName on AppLocalizations {
  String get proPlanName => '$appName PRO';
}
