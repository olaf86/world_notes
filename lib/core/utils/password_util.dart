/// Password strength validation for note locks.
///
/// NOTE on hashing: password *verification* is performed server-side by a
/// Cloud Function (Phase 3), which keeps the hash out of reach of clients —
/// storing the hash in a client-readable document would let an attacker read
/// it and forge an access grant.  The client only ever sends the plaintext
/// password to the Cloud Function over HTTPS; it never hashes locally.
///
/// This utility therefore covers only client-side strength checking before
/// the password is submitted.
abstract class PasswordUtil {
  PasswordUtil._();

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
