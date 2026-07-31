import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/config/bootstrap_world_catalog.dart';
import 'package:world_notes/config/world_catalog.dart';
import 'package:world_notes/presentation/providers/providers.dart';

void main() {
  test('starts in Asia and keeps home and selection separate', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(homeWorldProvider), asiaWorldId);
    expect(container.read(selectedWorldProvider), asiaWorldId);
    expect(container.read(worldSelectionProvider).selectedWorld, asiaWorldId);
  });

  test('rejects selection of a provisioning world', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      () => container
          .read(selectedWorldProvider.notifier)
          .selectWorld(const WorldId('europe')),
      throwsStateError,
    );
    expect(container.read(selectedWorldProvider), asiaWorldId);
  });

  test('switches only after the catalog enables content access', () {
    final catalog = WorldCatalog.fromJson(_enabledEuropeCatalog);
    final container = ProviderContainer(
      overrides: [worldCatalogProvider.overrideWithValue(catalog)],
    );
    addTearDown(container.dispose);

    container
        .read(selectedWorldProvider.notifier)
        .selectWorld(const WorldId('europe'));

    expect(container.read(homeWorldProvider), asiaWorldId);
    expect(
      container.read(worldSelectionProvider),
      isA<WorldSelection>()
          .having((value) => value.homeWorld, 'homeWorld', asiaWorldId)
          .having(
            (value) => value.selectedWorld,
            'selectedWorld',
            const WorldId('europe'),
          ),
    );
    expect(container.read(effectiveRegionProvider), 'europe-west1');
  });
}

const Map<String, Object?> _enabledEuropeCatalog = {
  'schemaVersion': 1,
  'catalogVersion': 1,
  'worlds': <Object?>[
    <String, Object?>{
      'worldId': 'asia',
      'databaseId': '(default)',
      'firestoreLocation': 'asia-northeast1',
      'functionsRegion': 'asia-northeast1',
      'bucketName': 'world-notes-prod.firebasestorage.app',
      'displayNameKey': 'world.asia',
      'catalogState': 'contentEnabled',
      'homeAssignmentEnabled': false,
      'contentAccessEnabled': true,
    },
    <String, Object?>{
      'worldId': 'europe',
      'databaseId': 'europe',
      'firestoreLocation': 'europe-west1',
      'functionsRegion': 'europe-west1',
      'bucketName': 'world-notes-prod-europe',
      'displayNameKey': 'world.europe',
      'catalogState': 'contentEnabled',
      'homeAssignmentEnabled': false,
      'contentAccessEnabled': true,
    },
  ],
};
