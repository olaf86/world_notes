import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/user_entity.dart';
import 'package:world_notes/presentation/providers/providers.dart';
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
}

class _FakeAdPrivacyService implements AdPrivacyService {
  int gatherCount = 0;

  @override
  Future<AdPrivacyStatus> gatherConsentAndInitialize() async {
    gatherCount += 1;
    return const AdPrivacyStatus(
      canRequestAds: true,
      privacyOptionsRequired: true,
    );
  }

  @override
  Future<void> showPrivacyOptions() async {}
}
