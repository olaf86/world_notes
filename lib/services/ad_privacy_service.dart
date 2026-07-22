import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdPrivacyStatus {
  final bool canRequestAds;
  final bool privacyOptionsRequired;

  const AdPrivacyStatus({
    required this.canRequestAds,
    required this.privacyOptionsRequired,
  });

  static const disabled = AdPrivacyStatus(
    canRequestAds: false,
    privacyOptionsRequired: false,
  );
}

abstract interface class AdPrivacyService {
  Future<AdPrivacyStatus> gatherConsentAndInitialize();
  Future<void> showPrivacyOptions();
}

/// Runs Google's UMP flow before initializing the Mobile Ads SDK.
///
/// When both European regulations and the iOS IDFA message are published in
/// AdMob, UMP presents them in the required order and triggers ATT after its
/// IDFA explanation. A declined ATT request does not prevent ad requests.
class GoogleAdPrivacyService implements AdPrivacyService {
  Future<AdPrivacyStatus>? _initialization;

  @override
  Future<AdPrivacyStatus> gatherConsentAndInitialize() {
    return _initialization ??= _gatherConsentAndInitialize();
  }

  Future<AdPrivacyStatus> _gatherConsentAndInitialize() async {
    final updateError = await _requestConsentInfoUpdate();
    if (updateError == null) {
      final formError = await _loadAndShowConsentFormIfRequired();
      if (formError != null) {
        debugPrint(
          '[AdMob] Consent form failed: ${formError.errorCode} '
          '${formError.message}',
        );
      }
    } else {
      debugPrint(
        '[AdMob] Consent update failed: ${updateError.errorCode} '
        '${updateError.message}',
      );
    }

    final consentInformation = ConsentInformation.instance;
    final canRequestAds = await consentInformation.canRequestAds();
    final privacyOptionsStatus = await consentInformation
        .getPrivacyOptionsRequirementStatus();

    if (canRequestAds) {
      await MobileAds.instance.initialize();
    }

    return AdPrivacyStatus(
      canRequestAds: canRequestAds,
      privacyOptionsRequired:
          privacyOptionsStatus == PrivacyOptionsRequirementStatus.required,
    );
  }

  Future<FormError?> _requestConsentInfoUpdate() {
    final completer = Completer<FormError?>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => completer.complete(),
      completer.complete,
    );
    return completer.future;
  }

  Future<FormError?> _loadAndShowConsentFormIfRequired() {
    final completer = Completer<FormError?>();
    ConsentForm.loadAndShowConsentFormIfRequired(completer.complete);
    return completer.future;
  }

  @override
  Future<void> showPrivacyOptions() async {
    final completer = Completer<FormError?>();
    ConsentForm.showPrivacyOptionsForm(completer.complete);
    final error = await completer.future;
    if (error != null) {
      throw StateError(
        'Unable to show privacy options (${error.errorCode}): '
        '${error.message}',
      );
    }
  }
}
