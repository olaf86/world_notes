import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/config/bootstrap_world_catalog.dart';
import 'package:world_notes/config/world_catalog.dart';
import 'package:world_notes/domain/entities/user_entity.dart';
import 'package:world_notes/presentation/providers/providers.dart';
import 'package:world_notes/services/account_bootstrap_service.dart';

void main() {
  test('starts in Asia and keeps home and selection separate', () {
    final container = ProviderContainer(
      overrides: [
        homeAssignmentProvider.overrideWith((ref) => Stream.value(null)),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(homeWorldProvider), asiaWorldId);
    expect(container.read(selectedWorldProvider), asiaWorldId);
    expect(container.read(worldSelectionProvider).selectedWorld, asiaWorldId);
    expect(
      container.read(selectedWorldNavigationProvider).note('note-1'),
      '/worlds/asia/notes/note-1',
    );
  });

  test('rejects selection of a world disabled by the active catalog', () async {
    final container = ProviderContainer(
      overrides: [
        worldCatalogProvider.overrideWithValue(
          WorldCatalog.fromJson(_disabledEuropeCatalog),
        ),
        homeAssignmentProvider.overrideWith((ref) => Stream.value(null)),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(selectedWorldProvider.notifier)
          .selectWorld(const WorldId('europe')),
      throwsStateError,
    );
    expect(container.read(selectedWorldProvider), asiaWorldId);
  });

  test('switches only after the catalog and local marker are ready', () async {
    final catalog = WorldCatalog.fromJson(_enabledEuropeCatalog);
    final container = ProviderContainer(
      overrides: [
        worldCatalogProvider.overrideWithValue(catalog),
        authStateProvider.overrideWith(
          (ref) => Stream.value(const UserEntity(id: 'user-1', name: 'User')),
        ),
        homeAssignmentProvider.overrideWith(
          (ref) => Stream.value(
            const HomeAssignment(homeWorld: asiaWorldId, epoch: 1),
          ),
        ),
        worldReadinessProvider.overrideWith((ref, worldId) async => true),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authStateProvider.future);
    await container.read(homeAssignmentProvider.future);
    await container
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
    expect(
      container.read(selectedWorldCatalogEntryProvider).functionsRegion,
      'europe-west1',
    );
    expect(
      container.read(selectedWorldNavigationProvider).note('note-1'),
      '/worlds/europe/notes/note-1',
    );
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

const Map<String, Object?> _disabledEuropeCatalog = {
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
      'catalogState': 'homeEnabled',
      'homeAssignmentEnabled': true,
      'contentAccessEnabled': true,
    },
    <String, Object?>{
      'worldId': 'europe',
      'databaseId': 'europe',
      'firestoreLocation': 'europe-west1',
      'functionsRegion': 'europe-west1',
      'bucketName': 'world-notes-prod-europe',
      'displayNameKey': 'world.europe',
      'catalogState': 'mirrorOnly',
      'homeAssignmentEnabled': false,
      'contentAccessEnabled': false,
    },
  ],
};
