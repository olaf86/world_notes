// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get locationPermissionTitle => 'Location Required';

  @override
  String get locationPermissionMessage =>
      'Enable location tracking to enjoy World Notes.';

  @override
  String get locationPermissionOpenSettings => 'Open Settings';

  @override
  String get locationPermissionAllow => 'Allow Location';

  @override
  String get locationServiceDisabledTitle => 'Turn On Location Services';

  @override
  String get locationServiceDisabledMessage =>
      'Turn on location services to use World Notes.';

  @override
  String get locationServiceOpenSettings => 'Open Location Settings';

  @override
  String get locationSearching => 'Finding your location…';
}
