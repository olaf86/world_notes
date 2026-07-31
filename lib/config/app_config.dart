import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'runtime_mode.dart';

class AppConfig {
  static const stadiaApiKey = String.fromEnvironment(
    'STADIA_API_KEY',
    defaultValue: '',
  );

  // MapLibre style using Stadia Maps (free tier)
  static const mapStyleUrl =
      'https://tiles.stadiamaps.com/styles/alidade_smooth.json';

  static String mapStyleUrlWithKey(String apiKey) {
    if (apiKey.isEmpty) return mapStyleUrl;
    return '$mapStyleUrl?api_key=$apiKey';
  }

  static const double defaultLatitude = 35.6812;
  static const double defaultLongitude = 139.7671;
  static const double defaultZoom = 14.0;

  // Ads
  static const String _bannerAdUnitIdOverride = String.fromEnvironment(
    'BANNER_AD_UNIT_ID',
    defaultValue: '',
  );
  static const String _interstitialAdUnitIdOverride = String.fromEnvironment(
    'INTERSTITIAL_AD_UNIT_ID',
    defaultValue: '',
  );
  static const String androidTestBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String iosTestBannerAdUnitId =
      'ca-app-pub-3940256099942544/2934735716';
  static const String androidTestInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/1033173712';
  static const String iosTestInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/4411468910';

  /// Distinct note details that must open without an interstitial after the
  /// previous interstitial impression.
  static const int interstitialMinimumNoteOpens = 2;

  /// Independent display chance for each new note after the minimum opens.
  static const double interstitialDisplayProbability = 0.20;

  /// A second guard in addition to the count/probability policy. Production
  /// should also configure an equivalent frequency cap in AdMob.
  static const Duration interstitialCooldown = Duration(minutes: 15);

  static const Duration bannerAdInitialRetryDelay = Duration(seconds: 30);
  static const Duration bannerAdMaxRetryDelay = Duration(minutes: 5);

  /// Returns `min(30 seconds * 2^failureCount, 5 minutes)`.
  /// Failures after reaching the cap continue to retry every five minutes.
  static Duration bannerAdRetryDelayForFailure(int failureCount) {
    assert(failureCount >= 0);
    final seconds = math.min(
      bannerAdInitialRetryDelay.inSeconds * math.pow(2, failureCount),
      bannerAdMaxRetryDelay.inSeconds,
    );
    return Duration(seconds: seconds.toInt());
  }

  static bool get supportsMobileAds {
    if (screenshotMode) return false;
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
  }

  static String get bannerAdUnitId {
    return bannerAdUnitIdFor(
      platform: defaultTargetPlatform,
      useProductionAds: kReleaseMode,
      productionAdUnitId: _bannerAdUnitIdOverride,
    );
  }

  static String get interstitialAdUnitId {
    return interstitialAdUnitIdFor(
      platform: defaultTargetPlatform,
      useProductionAds: kReleaseMode,
      productionAdUnitId: _interstitialAdUnitIdOverride,
    );
  }

  static String bannerAdUnitIdFor({
    required TargetPlatform platform,
    required bool useProductionAds,
    required String productionAdUnitId,
  }) {
    if (useProductionAds) return productionAdUnitId;
    return switch (platform) {
      TargetPlatform.iOS => iosTestBannerAdUnitId,
      TargetPlatform.android => androidTestBannerAdUnitId,
      _ => androidTestBannerAdUnitId,
    };
  }

  static String interstitialAdUnitIdFor({
    required TargetPlatform platform,
    required bool useProductionAds,
    required String productionAdUnitId,
  }) {
    if (useProductionAds) return productionAdUnitId;
    return switch (platform) {
      TargetPlatform.iOS => iosTestInterstitialAdUnitId,
      TargetPlatform.android => androidTestInterstitialAdUnitId,
      _ => androidTestInterstitialAdUnitId,
    };
  }

  /// Release builds never fall back to Google's demo units. CI must inject
  /// both production unit IDs before ads are enabled.
  static bool get hasRequiredAdUnitIds =>
      bannerAdUnitId.isNotEmpty && interstitialAdUnitId.isNotEmpty;

  // RevenueCat
  static const String revenueCatApiKeyIos = String.fromEnvironment(
    'REVENUECAT_API_KEY_IOS',
    defaultValue: '',
  );
  static const String revenueCatApiKeyAndroid = String.fromEnvironment(
    'REVENUECAT_API_KEY_ANDROID',
    defaultValue: '',
  );

  static const String proPlanName = 'World Notes PRO';
  static const String proEntitlementId = 'pro';
  static const String proMonthlyProductId = 'world_notes_pro_monthly';
  static const String proYearlyProductId = 'world_notes_pro_yearly';
  static const String proMonthlyPriceLabel = '¥300';
  static const String proYearlyPriceLabel = '¥2,980';
  static const String proYearlyLaunchPriceLabel = '¥1,980';
  static const String proMonthlyUsdPriceLabel = '\$2';
  static const String proYearlyUsdPriceLabel = '\$20';

  // Message pagination
  static const int messagesPageSize = 20;

  /// Delay used before sending optimistic like toggles to Cloud Functions.
  static const Duration likeDebounceDuration = Duration(milliseconds: 800);

  // ── Application constraints ───────────────────────────────────────────────

  /// Maximum number of messages allowed per note thread.
  /// Firestore rules enforce this server-side.
  static const int maxMessagesPerThread = 1000;

  /// Maximum distance from a note at which its detail can be opened for
  /// non-PRO users.
  /// Must match NOTE_DETAIL_ACCESS_RADIUS_KM in functions/src/constants.ts.
  static const int noteDetailAccessRadiusMeters = 500;

  /// Maximum distance from a note at which its detail can be opened for
  /// PRO users.
  /// Must match PRO_NOTE_DETAIL_ACCESS_RADIUS_KM in functions/src/constants.ts.
  static const int proNoteDetailAccessRadiusMeters = 1000;

  static int noteDetailAccessRadiusMetersFor({required bool isPremium}) {
    return isPremium
        ? proNoteDetailAccessRadiusMeters
        : noteDetailAccessRadiusMeters;
  }

  /// Maximum character length of a single message.
  static const int maxMessageLength = 2000;

  /// Maximum images that can be attached to a single message.
  static const int maxMessageImages = 4;

  /// Maximum delay before a scheduled message may be published.
  static const int maxMessagePublishDelayDays = 7;

  /// Maximum active notes a free user may own simultaneously.
  static const int freeNoteLimit = 20;

  /// Maximum active notes a PRO user may own simultaneously.
  static const int proNoteLimit = 200;

  /// Maximum visitor avatars shown in compact note-detail previews.
  static const int visitorPreviewCompactMax = 6;

  /// Maximum visitor avatars shown when the preview has wider horizontal room.
  static const int visitorPreviewExpandedMax = 10;

  /// Maximum image size (bytes) accepted for upload.
  static const int maxImageBytes = 5 * 1024 * 1024; // 5 MB

  /// Maximum lifetime of a note before it auto-archives.
  static const int maxNoteLifetimeDays = 365;

  /// Expiry presets (in days) offered when creating a note. Selection is
  /// required — a note can never be created without an expiry.
  static const List<int> noteExpiryPresetDays = [7, 30, 90, 180, 365];

  /// Default expiry preset pre-selected on the note creation screen (3 months).
  /// Must be one of [noteExpiryPresetDays].
  static const int defaultNoteExpiryDays = 90;

  /// Base URL for private-note invite links. The path is supplied by the
  /// selected-world navigation service and handled as a deep link once the
  /// domain is configured. Host: worldnotes.asobo.dev (Firebase Hosting).
  static const String inviteLinkBase = 'https://worldnotes.asobo.dev';
}
