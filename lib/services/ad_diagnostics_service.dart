import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_privacy_service.dart';

abstract interface class AdDiagnosticsService {
  Future<void> reportMissingConfiguration({
    required bool hasBannerAdUnitId,
    required bool hasInterstitialAdUnitId,
  });

  Future<void> reportPrivacyBlocked(AdPrivacyStatus status);

  Future<void> reportBannerLoadFailure(LoadAdError error);
}

/// Sends one diagnostic per failure category and app process to Crashlytics.
///
/// Production ad unit IDs are deliberately never included in diagnostics.
class FirebaseAdDiagnosticsService implements AdDiagnosticsService {
  final FirebaseCrashlytics crashlytics;
  final Set<String> _reportedKeys = {};

  FirebaseAdDiagnosticsService(this.crashlytics);

  @override
  Future<void> reportMissingConfiguration({
    required bool hasBannerAdUnitId,
    required bool hasInterstitialAdUnitId,
  }) {
    return _reportOnce(
      key: 'missing-configuration',
      error: StateError('AdMob release configuration is incomplete.'),
      information: [
        'bannerAdUnitIdConfigured=$hasBannerAdUnitId',
        'interstitialAdUnitIdConfigured=$hasInterstitialAdUnitId',
      ],
    );
  }

  @override
  Future<void> reportPrivacyBlocked(AdPrivacyStatus status) {
    return _reportOnce(
      key: 'privacy-blocked-retry-${status.shouldRetry}',
      error: StateError('Ad requests are blocked by the privacy gate.'),
      information: [
        'shouldRetry=${status.shouldRetry}',
        'privacyOptionsRequired=${status.privacyOptionsRequired}',
      ],
    );
  }

  @override
  Future<void> reportBannerLoadFailure(LoadAdError error) {
    return _reportOnce(
      key: 'banner-load-${error.domain}-${error.code}',
      error: error,
      information: [
        'domain=${error.domain}',
        'code=${error.code}',
        'message=${error.message}',
        if (error.responseInfo != null) 'responseInfo=${error.responseInfo}',
      ],
    );
  }

  Future<void> _reportOnce({
    required String key,
    required Object error,
    required List<String> information,
  }) async {
    if (!_reportedKeys.add(key)) return;

    final message = '[AdMob] $key: ${information.join(', ')}';
    debugPrint(message);
    try {
      await crashlytics.log(message);
      await crashlytics.recordError(
        error,
        StackTrace.current,
        reason: 'AdMob diagnostics: $key',
        information: information,
      );
    } catch (reportingError) {
      debugPrint('[AdMob] Could not report diagnostics: $reportingError');
    }
  }
}
