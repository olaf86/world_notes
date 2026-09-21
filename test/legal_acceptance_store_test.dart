import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:world_notes/config/app_config.dart';
import 'package:world_notes/domain/entities/legal_acceptance.dart';
import 'package:world_notes/services/legal_acceptance_store.dart';

void main() {
  test('keeps legal acceptance isolated by account', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = LegalAcceptanceStore(preferences);

    await store.writeCurrent('accepted-user');

    expect(
      store.readCurrent('accepted-user'),
      isA<LegalAcceptance>()
          .having(
            (value) => value.serviceTermsVersion,
            'service terms version',
            AppConfig.currentServiceTermsVersion,
          )
          .having(
            (value) => value.privacyPolicyVersion,
            'privacy policy version',
            AppConfig.currentPrivacyPolicyVersion,
          ),
    );
    expect(store.readCurrent('another-user'), isNull);
  });

  test('does not treat stale versions as current', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = LegalAcceptanceStore(preferences);

    await store.write(
      'user-1',
      const LegalAcceptance(
        serviceTermsVersion: 'old-terms',
        privacyPolicyVersion: 'old-privacy',
      ),
    );

    expect(store.read('user-1'), isNotNull);
    expect(store.readCurrent('user-1'), isNull);
  });
}
