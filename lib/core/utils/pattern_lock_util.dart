abstract class PatternLockUtil {
  PatternLockUtil._();

  static const int maxLength = 30;
  static const String prefix = 'pattern:v1:';

  static String? validate(List<int> path) {
    if (path.isEmpty) {
      return 'Draw a pattern to lock this note.';
    }
    if (path.length > maxLength) {
      return 'Pattern is too long. Use $maxLength nodes or fewer.';
    }
    if (path.any((node) => node < 0 || node > 8)) {
      return 'Pattern contains an invalid node.';
    }
    for (var i = 1; i < path.length; i++) {
      if (!areAdjacent(path[i - 1], path[i])) {
        return 'Pattern can only connect neighboring dots.';
      }
    }
    return null;
  }

  static bool areAdjacent(int a, int b) {
    if (a == b) return false;
    final ax = a % 3;
    final ay = a ~/ 3;
    final bx = b % 3;
    final by = b ~/ 3;
    return (ax - bx).abs() <= 1 && (ay - by).abs() <= 1;
  }

  static String encode(List<int> path) {
    final error = validate(path);
    if (error != null) {
      throw ArgumentError(error);
    }
    return '$prefix${path.join()}';
  }

  static bool isEncoded(String value) {
    if (!value.startsWith(prefix)) return false;
    final encodedPath = value.substring(prefix.length);
    if (!RegExp(r'^[0-8]{1,30}$').hasMatch(encodedPath)) return false;
    final path = encodedPath.split('').map(int.parse).toList();
    return validate(path) == null;
  }
}
