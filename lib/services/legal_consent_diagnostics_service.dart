import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Reports legal-consent submission failures without attaching account data.
abstract interface class LegalConsentDiagnosticsService {
  Future<void> reportSubmissionFailure(Object error, StackTrace stack);
}

final class FirebaseLegalConsentDiagnosticsService
    implements LegalConsentDiagnosticsService {
  const FirebaseLegalConsentDiagnosticsService(this._crashlytics);

  final FirebaseCrashlytics _crashlytics;

  @override
  Future<void> reportSubmissionFailure(Object error, StackTrace stack) async {
    if (error is! FirebaseFunctionsException) return;

    final information = buildLegalConsentFailureInformation(
      code: error.code,
      message: error.message,
      details: error.details,
    );
    try {
      await _crashlytics.log('[LegalConsent] acceptServiceTerms failed');
      await _crashlytics.recordError(
        StateError('acceptServiceTerms callable failed.'),
        stack,
        reason: 'Legal consent submission failed',
        information: information,
        fatal: false,
      );
    } catch (reportingError, reportingStack) {
      debugPrint(
        '[LegalConsent] Could not report failure to Crashlytics: '
        '$reportingError\n$reportingStack',
      );
    }
  }
}

/// Builds bounded diagnostics from server-controlled callable error fields.
///
/// Request data, account identifiers, and arbitrary detail fields are never
/// included. Callable details are restricted to non-personal routing/reason
/// fields emitted by the trusted backend.
@visibleForTesting
List<String> buildLegalConsentFailureInformation({
  required String code,
  required String? message,
  required Object? details,
}) {
  final information = <String>[
    'functionsCode=${_boundedSingleLine(code, maxLength: 64)}',
    'functionsMessage=${_boundedSingleLine(message, maxLength: 240)}',
  ];

  if (details is Map) {
    const allowedKeys = ['reason', 'worldId', 'homeWorld'];
    for (final key in allowedKeys) {
      final value = details[key];
      if (value is String && _safeDetailValue.hasMatch(value)) {
        information.add('$key=$value');
      }
    }
    final omittedCount = details.keys
        .where((key) => !allowedKeys.contains(key))
        .length;
    if (omittedCount > 0) information.add('detailsOmitted=$omittedCount');
  } else if (details != null) {
    information.add('detailsOmitted=1');
  }

  return information;
}

final RegExp _safeDetailValue = RegExp(r'^[A-Za-z0-9._-]{1,80}$');

String _boundedSingleLine(String? value, {required int maxLength}) {
  final normalized = value
      ?.replaceAll(RegExp(r'[\u0000-\u001f\u007f]+'), ' ')
      .trim();
  if (normalized == null || normalized.isEmpty) return '<none>';
  if (normalized.length <= maxLength) return normalized;
  return normalized.substring(0, maxLength);
}
