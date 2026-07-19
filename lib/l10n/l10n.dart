import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

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
