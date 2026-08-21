import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/core/utils/password_util.dart';

void main() {
  group('PasswordUtil', () {
    test('allows arbitrary non-empty strings up to the maximum length', () {
      expect(PasswordUtil.validationError('abc'), isNull);
      expect(PasswordUtil.validationError('spaces and symbols !?'), isNull);
      expect(
        PasswordUtil.validationError('x' * PasswordUtil.maxLength),
        isNull,
      );
    });

    test('rejects empty and overlong strings', () {
      expect(PasswordUtil.validationError(''), PasswordValidationError.empty);
      expect(
        PasswordUtil.validationError('x' * (PasswordUtil.maxLength + 1)),
        PasswordValidationError.tooLong,
      );
    });

    test('validates confirmation', () {
      expect(
        PasswordUtil.confirmationValidationError(
          password: 'secret',
          confirmation: 'secret',
        ),
        isNull,
      );
      expect(
        PasswordUtil.confirmationValidationError(
          password: '',
          confirmation: '',
        ),
        PasswordValidationError.empty,
      );
      expect(
        PasswordUtil.confirmationValidationError(
          password: 'secret',
          confirmation: '',
        ),
        PasswordValidationError.confirmationEmpty,
      );
      expect(
        PasswordUtil.confirmationValidationError(
          password: 'secret',
          confirmation: 'different',
        ),
        PasswordValidationError.mismatch,
      );
    });
  });
}
