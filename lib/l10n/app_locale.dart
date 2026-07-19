import 'package:flutter/widgets.dart';

const supportedAppLocaleTags = <String>{'en', 'ja', 'zh_Hant', 'zh_Hans', 'ko'};

/// Parses the locale tags accepted by dart-defines and screenshot scripts.
Locale appLocaleFromTag(String tag) {
  final normalized = tag.replaceAll('-', '_');
  if (!supportedAppLocaleTags.contains(normalized)) return const Locale('ja');
  final parts = normalized.split('_');
  if (parts.length == 2) {
    return Locale.fromSubtags(languageCode: parts[0], scriptCode: parts[1]);
  }
  return Locale(parts[0]);
}
