import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/note_theme.dart';

void main() {
  test('parses each built-in note theme id', () {
    for (final theme in NoteThemeId.values) {
      expect(NoteThemeId.fromJson(theme.toJson()), theme);
    }
  });

  test('rejects missing and unsupported stored theme ids', () {
    expect(() => NoteThemeId.fromJson(null), throwsArgumentError);
    expect(() => NoteThemeId.fromJson('custom'), throwsArgumentError);
  });
}
