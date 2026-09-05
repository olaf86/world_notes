import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('store screenshot runners prepare the current app before capture', () {
    final runners = {
      'scripts/run_screenshots_ios.sh': 'ios',
      'scripts/run_screenshots_ipad.sh': 'ios',
      'scripts/run_screenshots_android.sh': 'android',
    };

    for (final MapEntry(key: path, value: platform) in runners.entries) {
      final script = File(path).readAsStringSync();
      expect(
        script,
        contains('bash scripts/prepare_screenshot_app.sh $platform'),
        reason: '$path must install a build from the current checkout',
      );
    }
  });

  test('screenshot app preparation is deterministic', () {
    final script = File('scripts/prepare_screenshot_app.sh').readAsStringSync();

    expect(script, contains('--dart-define=SCREENSHOT_MODE=true'));
    expect(script, contains('--dart-define=SCREENSHOT_LOCALE='));
    expect(script, contains('simctl ui booted appearance light'));
    expect(script, contains('adb shell cmd uimode night no'));
    expect(script, contains('flutter build ios'));
    expect(script, contains('flutter build apk'));
  });
}
