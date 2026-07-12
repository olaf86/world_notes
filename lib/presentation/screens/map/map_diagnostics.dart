import 'package:flutter/foundation.dart';

const bool _mapDiagnosticsEnabled = bool.fromEnvironment(
  'MAP_DIAGNOSTICS',
  defaultValue: true,
);

void logMapDiagnostics(String message) {
  if (!kDebugMode || !_mapDiagnosticsEnabled) return;
  debugPrint('[WorldNotesMap] ${DateTime.now().toIso8601String()} $message');
}
