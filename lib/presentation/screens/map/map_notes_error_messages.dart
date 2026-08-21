import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';

void showMapNotesRefreshErrorSnackBar(BuildContext context) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(context.l10n.mapNotesRefreshFailed)));
}

Future<void> reportMapNotesError({
  required FirebaseCrashlytics crashlytics,
  required String operation,
  required Object error,
  required StackTrace stack,
}) async {
  try {
    await crashlytics.setCustomKey('map_notes_operation', operation);
    await crashlytics.recordError(
      error,
      stack,
      reason: 'Map notes operation failed: $operation',
      fatal: false,
    );
  } catch (crashlyticsError, crashlyticsStack) {
    debugPrint(
      '[MapNotes] Could not report failure to Crashlytics: '
      '$crashlyticsError\n$crashlyticsStack',
    );
  }
}
