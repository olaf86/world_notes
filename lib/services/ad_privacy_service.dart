import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdPrivacyStatus {
  final bool canRequestAds;
  final bool privacyOptionsRequired;
  final bool shouldRetry;

  const AdPrivacyStatus({
    required this.canRequestAds,
    required this.privacyOptionsRequired,
    this.shouldRetry = false,
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
  final Future<AdPrivacyStatus> Function()? _initializerOverride;
  Future<AdPrivacyStatus>? _initialization;

  GoogleAdPrivacyService() : _initializerOverride = null;

  @visibleForTesting
  GoogleAdPrivacyService.forTesting(this._initializerOverride);

  @override
  Future<AdPrivacyStatus> gatherConsentAndInitialize() {
    final existing = _initialization;
    if (existing != null) return existing;

    final initialization =
        _initializerOverride?.call() ?? _gatherConsentAndInitialize();
    _initialization = initialization;
    // A retryable result or thrown platform error must not remain cached for
    // the entire app process. WorldNotesApp invalidates the provider when the
    // app next resumes, which starts a fresh UMP request.
    unawaited(
      initialization.then<void>(
        (status) {
          if (status.shouldRetry &&
              identical(_initialization, initialization)) {
            _initialization = null;
          }
        },
        onError: (Object _, StackTrace _) {
          if (identical(_initialization, initialization)) {
            _initialization = null;
          }
        },
      ),
    );
    return initialization;
  }

  Future<AdPrivacyStatus> _gatherConsentAndInitialize() async {
    final updateError = await _requestConsentInfoUpdate();
    FormError? formError;
    if (updateError == null) {
      formError = await _loadAndShowConsentFormIfRequired();
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
      shouldRetry: !canRequestAds && (updateError != null || formError != null),
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
