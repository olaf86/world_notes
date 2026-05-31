import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Password hashing and validation utilities for note lock/unlock.
///
/// Security approach (MVP):
///   HMAC-SHA256 keyed by the placeId is used instead of plain SHA-256.
///   This makes the hash place-specific — the same password on two different
///   notes produces different hashes, rendering generic rainbow tables useless.
///
/// Future improvement:
///   Move verification to a Cloud Function so the hash is never exposed to
///   clients and brute-force attempts can be rate-limited server-side.
abstract class PasswordUtil {
  PasswordUtil._();

  /// Computes HMAC-SHA256 of [password] keyed by [placeId].
  static String hash(String password, String placeId) {
    final key = utf8.encode(placeId);
    final bytes = utf8.encode(password);
    final hmac = Hmac(sha256, key);
    return hmac.convert(bytes).toString();
  }

  /// Returns true when [entered] matches the stored [hash] for [placeId].
  static bool verify(String entered, String hash, String placeId) {
    return PasswordUtil.hash(entered, placeId) == hash;
  }

  // ── Strength validation ───────────────────────────────────────────────────

  static const int minLength = 8;

  /// Returns null if [password] meets strength requirements, or a
  /// human-readable error string if it does not.
  static String? validate(String password) {
    if (password.length < minLength) {
      return 'Password must be at least $minLength characters.';
    }
    if (!password.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter.';
    }
    if (!password.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter.';
    }
    if (!password.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one digit.';
    }
    if (!password.contains(RegExp(r'[^A-Za-z0-9]'))) {
      return 'Password must contain at least one special character.';
    }
    return null; // valid
  }
}
