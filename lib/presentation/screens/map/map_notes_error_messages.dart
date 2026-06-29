import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

const mapNotesLoadErrorMessage =
    'Could not load nearby notes. Please try again.';
const mapNotesRefreshErrorMessage =
    'Could not refresh nearby notes. Please try again.';
const mapNoteOpenErrorMessage =
    'Could not open this note. Please try again when you are nearby.';

void showMapNotesRefreshErrorSnackBar(BuildContext context) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text(mapNotesRefreshErrorMessage)));
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
