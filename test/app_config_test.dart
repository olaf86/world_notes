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
    expect(
      AppConfig.interstitialAdUnitId,
      AppConfig.androidTestInterstitialAdUnitId,
    );
  });

  test('uses the official iOS test banner ad unit by default', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    expect(AppConfig.supportsMobileAds, isTrue);
    expect(AppConfig.bannerAdUnitId, AppConfig.iosTestBannerAdUnitId);
    expect(
      AppConfig.interstitialAdUnitId,
      AppConfig.iosTestInterstitialAdUnitId,
    );
  });

  test('uses an injected iOS interstitial unit for release builds', () {
    expect(
      AppConfig.interstitialAdUnitIdFor(
        platform: TargetPlatform.iOS,
        useProductionAds: true,
        productionAdUnitId: 'ios-production-interstitial',
      ),
      'ios-production-interstitial',
    );
  });

  test('uses an injected Android banner unit for release builds', () {
    expect(
      AppConfig.bannerAdUnitIdFor(
        platform: TargetPlatform.android,
        useProductionAds: true,
        productionAdUnitId: 'android-production-banner',
      ),
      'android-production-banner',
    );
  });

  test('release builds never fall back to a demo ad unit', () {
    expect(
      AppConfig.interstitialAdUnitIdFor(
        platform: TargetPlatform.iOS,
        useProductionAds: true,
        productionAdUnitId: '',
      ),
      isEmpty,
    );
  });

  test('keeps the official iOS interstitial test unit outside release', () {
    expect(
      AppConfig.interstitialAdUnitIdFor(
        platform: TargetPlatform.iOS,
        useProductionAds: false,
        productionAdUnitId: 'ignored-production-id',
      ),
      AppConfig.iosTestInterstitialAdUnitId,
    );
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

  test('uses the agreed note-open interstitial frequency defaults', () {
    expect(AppConfig.interstitialMinimumNoteOpens, 2);
    expect(AppConfig.interstitialDisplayProbability, 0.20);
    expect(AppConfig.interstitialCooldown, const Duration(minutes: 15));
  });

  test('backs off banner retries and caps the delay', () {
    expect(
      AppConfig.bannerAdRetryDelayForFailure(0),
      const Duration(seconds: 30),
    );
    expect(
      AppConfig.bannerAdRetryDelayForFailure(2),
      const Duration(minutes: 2),
    );
    expect(
      AppConfig.bannerAdRetryDelayForFailure(3),
      const Duration(minutes: 4),
    );
    expect(
      AppConfig.bannerAdRetryDelayForFailure(20),
      const Duration(minutes: 5),
    );
  });
}
