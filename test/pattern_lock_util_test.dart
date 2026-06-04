import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/core/utils/pattern_lock_util.dart';

void main() {
  group('PatternLockUtil', () {
    test('encodes a valid neighboring path', () {
      expect(PatternLockUtil.encode([0]), 'pattern:v1:0');
      expect(PatternLockUtil.encode([0, 1, 4, 8]), 'pattern:v1:0148');
    });

    test('rejects non-neighbor jumps', () {
      expect(
        PatternLockUtil.validate([0, 2]),
        'Pattern can only connect neighboring dots.',
      );
    });

    test('rejects patterns longer than the maximum length', () {
      final path = List<int>.filled(PatternLockUtil.maxLength + 1, 4);

      expect(
        PatternLockUtil.validate(path),
        'Pattern is too long. Use 30 nodes or fewer.',
      );
    });
  });
}
