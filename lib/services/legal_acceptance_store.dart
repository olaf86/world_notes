import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../domain/entities/legal_acceptance.dart';

/// Per-account local cache of a server-confirmed legal acceptance.
///
/// The cache keeps ordinary launches off the network. A missing or stale cache
/// still falls back to Firestore, so installing on another device or changing
/// a legal-document version remains safe.
final class LegalAcceptanceStore {
  const LegalAcceptanceStore(this._preferences);

  final SharedPreferences? _preferences;

  LegalAcceptance? read(String userId) {
    final preferences = _preferences;
    if (preferences == null) return null;
    final serviceTermsVersion = preferences.getString(
      _key(userId, 'serviceTermsVersion'),
    );
    final privacyPolicyVersion = preferences.getString(
      _key(userId, 'privacyPolicyVersion'),
    );
    if (serviceTermsVersion == null && privacyPolicyVersion == null) {
      return null;
    }
    return LegalAcceptance(
      serviceTermsVersion: serviceTermsVersion,
      privacyPolicyVersion: privacyPolicyVersion,
    );
  }

  LegalAcceptance? readCurrent(String userId) {
    final acceptance = read(userId);
    return acceptance?.matches(
              serviceTermsVersion: AppConfig.currentServiceTermsVersion,
              privacyPolicyVersion: AppConfig.currentPrivacyPolicyVersion,
            ) ==
            true
        ? acceptance
        : null;
  }

  Future<void> write(String userId, LegalAcceptance acceptance) async {
    final preferences = _preferences;
    final serviceTermsVersion = acceptance.serviceTermsVersion;
    final privacyPolicyVersion = acceptance.privacyPolicyVersion;
    if (preferences == null ||
        serviceTermsVersion == null ||
        privacyPolicyVersion == null) {
      return;
    }
    await preferences.setString(
      _key(userId, 'serviceTermsVersion'),
      serviceTermsVersion,
    );
    await preferences.setString(
      _key(userId, 'privacyPolicyVersion'),
      privacyPolicyVersion,
    );
  }

  Future<void> writeCurrent(String userId) => write(
    userId,
    const LegalAcceptance(
      serviceTermsVersion: AppConfig.currentServiceTermsVersion,
      privacyPolicyVersion: AppConfig.currentPrivacyPolicyVersion,
    ),
  );

  String _key(String userId, String field) => 'legalAcceptance.$userId.$field';
}
