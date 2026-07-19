import 'package:intl/intl.dart';

/// Human-readable "time until expiry" label for a note.
///
/// Examples: "Expired", "Expires in 5 hours", "Expires in 3 days",
/// "Expires in 4 months".
String remainingLifetimeLabel(DateTime expiresAt, {DateTime? now}) {
  final base = now ?? DateTime.now();
  final d = expiresAt.difference(base);

  if (d.isNegative) return 'Expired';
  if (d.inDays >= 60) return 'Expires in ${(d.inDays / 30).round()} months';
  if (d.inDays >= 1) {
    return 'Expires in ${d.inDays} day${d.inDays == 1 ? '' : 's'}';
  }
  if (d.inHours >= 1) {
    return 'Expires in ${d.inHours} hour${d.inHours == 1 ? '' : 's'}';
  }
  return 'Expires soon';
}

/// Compact absolute timestamp for note metadata.
String noteDateTimeLabel(DateTime value, {String? locale}) {
  return DateFormat.yMMMd(locale).add_Hm().format(value.toLocal());
}
