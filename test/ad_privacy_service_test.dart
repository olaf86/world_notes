import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/services/ad_privacy_service.dart';

void main() {
  test('retries a consent initialization marked as retryable', () async {
    var callCount = 0;
    final service = GoogleAdPrivacyService.forTesting(() async {
      callCount += 1;
      return const AdPrivacyStatus(
        canRequestAds: false,
        privacyOptionsRequired: false,
        shouldRetry: true,
      );
    });

    await service.gatherConsentAndInitialize();
    await Future<void>.delayed(Duration.zero);
    await service.gatherConsentAndInitialize();

    expect(callCount, 2);
  });

  test('shares a successful consent initialization', () async {
    var callCount = 0;
    final service = GoogleAdPrivacyService.forTesting(() async {
      callCount += 1;
      return const AdPrivacyStatus(
        canRequestAds: true,
        privacyOptionsRequired: false,
      );
    });

    await service.gatherConsentAndInitialize();
    await service.gatherConsentAndInitialize();

    expect(callCount, 1);
  });

  test('allows retry after consent initialization throws', () async {
    var callCount = 0;
    final service = GoogleAdPrivacyService.forTesting(() async {
      callCount += 1;
      if (callCount == 1) throw StateError('offline');
      return const AdPrivacyStatus(
        canRequestAds: true,
        privacyOptionsRequired: false,
      );
    });

    await expectLater(
      service.gatherConsentAndInitialize(),
      throwsA(isA<StateError>()),
    );
    await Future<void>.delayed(Duration.zero);
    await service.gatherConsentAndInitialize();

    expect(callCount, 2);
  });
}
