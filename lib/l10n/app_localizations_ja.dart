// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get locationPermissionTitle => '現在位置へのアクセスが必要です';

  @override
  String get locationPermissionMessage =>
      'World Notes を楽しむために、現在位置のトラッキング許可を有効にしてください。';

  @override
  String get locationPermissionOpenSettings => '設定を開く';

  @override
  String get locationSearching => '現在位置を取得中…';
}
