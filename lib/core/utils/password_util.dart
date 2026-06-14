/// String password validation for note locks.
///
/// NOTE on hashing: password *verification* is performed server-side by a
/// Cloud Function (Phase 3), which keeps the hash out of reach of clients —
/// storing the hash in a client-readable document would let an attacker read
/// it and forge an access grant.  The client only ever sends the plaintext
/// password to the Cloud Function over HTTPS; it never hashes locally.
///
/// This utility therefore covers only client-side shape checking before the
/// password is submitted.
abstract class PasswordUtil {
  PasswordUtil._();

  static const int maxLength = 30;

  /// Returns null if [password] meets configuration requirements, or a
  /// human-readable error string if it does not.
  static String? validate(String password) {
    if (password.isEmpty) {
      return 'Enter a password.';
    }
    if (password.length > maxLength) {
      return 'Password must be $maxLength characters or fewer.';
    }
    return null; // valid
  }

  static String? validateConfirmation({
    required String password,
    required String confirmation,
  }) {
    final passwordError = validate(password);
    if (passwordError != null) return passwordError;
    if (confirmation.isEmpty) {
      return 'Re-enter the password.';
    }
    if (password != confirmation) {
      return 'Passwords do not match.';
    }
    return null;
  }
}
