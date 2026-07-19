import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// Returns active translations, with a fallback for isolated widget tests
/// whose minimal app does not register localization delegates.
AppLocalizations appLocalizationsOf(BuildContext context) {
  return AppLocalizations.of(context) ??
      lookupAppLocalizations(Localizations.localeOf(context));
}
