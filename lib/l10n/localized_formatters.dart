import 'package:intl/intl.dart';

import 'app_localizations.dart';

/// Formats an absolute timestamp used in note metadata.
String formatNoteDateTime(DateTime value, {required String locale}) {
  return DateFormat.yMMMd(locale).add_Hm().format(value.toLocal());
}

/// Formats a message timestamp, omitting the date for recent messages.
String formatMessageDateTime(
  DateTime value, {
  required String locale,
  required bool includeDate,
}) {
  final localValue = value.toLocal();
  return includeDate
      ? DateFormat.MMMd(locale).add_Hm().format(localValue)
      : DateFormat.Hm(locale).format(localValue);
}

/// Formats a relative timestamp using complete phrases from the ARB bundle.
String formatRelativeTime(
  AppLocalizations l10n,
  DateTime value, {
  DateTime? now,
}) {
  final difference = (now ?? DateTime.now()).difference(value);
  if (difference.inDays >= 1) return l10n.relativeDaysAgo(difference.inDays);
  if (difference.inHours >= 1) {
    return l10n.relativeHoursAgo(difference.inHours);
  }
  if (difference.inMinutes >= 1) {
    return l10n.relativeMinutesAgo(difference.inMinutes);
  }
  return l10n.relativeJustNow;
}

/// Formats the remaining lifetime of a note using complete ARB phrases.
String formatRemainingLifetime(
  AppLocalizations l10n,
  DateTime expiresAt, {
  DateTime? now,
}) {
  final duration = expiresAt.difference(now ?? DateTime.now());
  if (duration.isNegative) return l10n.noteExpired;
  if (duration.inDays >= 60) {
    return l10n.noteExpiresMonths((duration.inDays / 30).round());
  }
  if (duration.inDays >= 1) return l10n.noteExpiresDays(duration.inDays);
  if (duration.inHours >= 1) return l10n.noteExpiresHours(duration.inHours);
  return l10n.noteExpiresSoon;
}
