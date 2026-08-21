/// Password validation for note locks.
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

  /// Returns a locale-independent error that the presentation layer converts
  /// to user-facing copy, or null when [password] is valid.
  static PasswordValidationError? validationError(String password) {
    if (password.isEmpty) {
      return PasswordValidationError.empty;
    }
    if (password.length > maxLength) {
      return PasswordValidationError.tooLong;
    }
    return null;
  }

  static PasswordValidationError? confirmationValidationError({
    required String password,
    required String confirmation,
  }) {
    final passwordError = validationError(password);
    if (passwordError != null) return passwordError;
    if (confirmation.isEmpty) {
      return PasswordValidationError.confirmationEmpty;
    }
    if (password != confirmation) {
      return PasswordValidationError.mismatch;
    }
    return null;
  }
}

enum PasswordValidationError { empty, tooLong, confirmationEmpty, mismatch }
