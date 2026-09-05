import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/core/theme/app_theme.dart';
import 'package:world_notes/core/utils/place_icon.dart';

void main() {
  test('uses the app note color when a stored color is invalid', () {
    expect(parsePlaceColor('not-a-color'), AppTheme.defaultNoteColor);
  });
}
