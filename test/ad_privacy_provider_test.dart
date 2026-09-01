import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:world_notes/domain/entities/user_entity.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/services/ad_diagnostics_service.dart';
import 'package:world_notes/services/ad_privacy_service.dart';

void main() {
  test('gathers consent after a non-premium user is authenticated', () async {
    final service = _FakeAdPrivacyService();
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) =>
              Stream.value(const UserEntity(id: 'user-1', name: 'Test user')),
        ),
        isPremiumProvider.overrideWith((ref) => Stream.value(false)),
        adPrivacyServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authStateProvider.future);
    await container.read(isPremiumProvider.future);
    final status = await container.read(adPrivacyStatusProvider.future);

    expect(service.gatherCount, 1);
    expect(status.canRequestAds, isTrue);
    expect(container.read(canRequestAdsProvider), isTrue);
  });

  test('does not gather ad consent for a premium user', () async {
    final service = _FakeAdPrivacyService();
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) =>
              Stream.value(const UserEntity(id: 'user-1', name: 'Test user')),
        ),
        isPremiumProvider.overrideWith((ref) => Stream.value(true)),
        adPrivacyServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authStateProvider.future);
    await container.read(isPremiumProvider.future);
    final status = await container.read(adPrivacyStatusProvider.future);

    expect(service.gatherCount, 0);
    expect(status.canRequestAds, isFalse);
  });

  test('reports when the privacy gate blocks ad requests', () async {
    final service = _FakeAdPrivacyService(
      status: const AdPrivacyStatus(
        canRequestAds: false,
        privacyOptionsRequired: false,
        shouldRetry: true,
      ),
    );
    final diagnostics = _FakeAdDiagnosticsService();
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) =>
              Stream.value(const UserEntity(id: 'user-1', name: 'Test user')),
        ),
        isPremiumProvider.overrideWith((ref) => Stream.value(false)),
        adPrivacyServiceProvider.overrideWithValue(service),
        adDiagnosticsServiceProvider.overrideWithValue(diagnostics),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authStateProvider.future);
    await container.read(isPremiumProvider.future);
    final status = await container.read(adPrivacyStatusProvider.future);

    expect(status.canRequestAds, isFalse);
    expect(diagnostics.privacyBlockedStatuses, [status]);
  });
}

class _FakeAdPrivacyService implements AdPrivacyService {
  final AdPrivacyStatus status;
  int gatherCount = 0;

  _FakeAdPrivacyService({
    this.status = const AdPrivacyStatus(
      canRequestAds: true,
      privacyOptionsRequired: true,
    ),
  });

  @override
  Future<AdPrivacyStatus> gatherConsentAndInitialize() async {
    gatherCount += 1;
    return status;
  }

  @override
  Future<void> showPrivacyOptions() async {}
}

class _FakeAdDiagnosticsService implements AdDiagnosticsService {
  final List<AdPrivacyStatus> privacyBlockedStatuses = [];

  @override
  Future<void> reportBannerLoadFailure(LoadAdError error) async {}

  @override
  Future<void> reportMissingConfiguration({
    required bool hasBannerAdUnitId,
    required bool hasInterstitialAdUnitId,
  }) async {}

  @override
  Future<void> reportPrivacyBlocked(AdPrivacyStatus status) async {
    privacyBlockedStatuses.add(status);
  }
}
