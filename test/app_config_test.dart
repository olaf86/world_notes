import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/config/app_config.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('uses the official Android test banner ad unit by default', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    expect(AppConfig.supportsMobileAds, isTrue);
    expect(AppConfig.bannerAdUnitId, AppConfig.androidTestBannerAdUnitId);
  });

  test('uses the official iOS test banner ad unit by default', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    expect(AppConfig.supportsMobileAds, isTrue);
    expect(AppConfig.bannerAdUnitId, AppConfig.iosTestBannerAdUnitId);
  });

  test('does not support mobile ads on desktop platforms', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    expect(AppConfig.supportsMobileAds, isFalse);
  });

  test('uses extended note access radius for premium users', () {
    expect(
      AppConfig.noteDetailAccessRadiusMetersFor(isPremium: false),
      AppConfig.noteDetailAccessRadiusMeters,
    );
    expect(
      AppConfig.noteDetailAccessRadiusMetersFor(isPremium: true),
      AppConfig.proNoteDetailAccessRadiusMeters,
    );
    expect(AppConfig.proNoteDetailAccessRadiusMeters, 1000);
  });
}
