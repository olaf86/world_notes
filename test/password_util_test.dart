import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/core/utils/password_util.dart';

void main() {
  group('PasswordUtil', () {
    test('allows arbitrary non-empty strings up to the maximum length', () {
      expect(PasswordUtil.validate('abc'), isNull);
      expect(PasswordUtil.validate('spaces and symbols !?'), isNull);
      expect(PasswordUtil.validate('x' * PasswordUtil.maxLength), isNull);
    });

    test('rejects empty and overlong strings', () {
      expect(PasswordUtil.validate(''), 'Enter a password.');
      expect(
        PasswordUtil.validate('x' * (PasswordUtil.maxLength + 1)),
        'Password must be 30 characters or fewer.',
      );
    });
  });
}
