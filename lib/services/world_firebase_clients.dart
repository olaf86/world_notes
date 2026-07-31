import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../config/world_catalog.dart';

typedef WorldClientBuilder<T> = T Function(WorldCatalogEntry world);

/// A callable Functions client permanently bound to one world route.
///
/// Every request carries the world ID and every response must echo the same
/// trusted world ID. Feature code therefore cannot accidentally call a
/// regional function without declaring its data world.
final class WorldFunctionsClient {
  const WorldFunctionsClient({
    required WorldId worldId,
    required FirebaseFunctions functions,
  }) : _worldId = worldId,
       _functions = functions;

  final WorldId _worldId;
  final FirebaseFunctions _functions;

  WorldHttpsCallable httpsCallable(String name) {
    return WorldHttpsCallable(
      worldId: _worldId,
      callable: _functions.httpsCallable(name),
    );
  }
}

/// A single callable endpoint bound to a [WorldFunctionsClient].
final class WorldHttpsCallable {
  const WorldHttpsCallable({
    required WorldId worldId,
    required HttpsCallable callable,
  }) : _worldId = worldId,
       _callable = callable;

  final WorldId _worldId;
  final HttpsCallable _callable;

  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    final data = switch (parameters) {
      null => <String, dynamic>{},
      Map<String, dynamic>() => Map<String, dynamic>.from(parameters),
      _ => throw ArgumentError.value(
        parameters,
        'parameters',
        'World callables require a string-keyed map.',
      ),
    };
    data['worldId'] = _worldId.value;

    final result = await _callable.call<T>(data);
    final dynamic responseData = result.data;
    if (responseData is! Map || responseData['worldId'] != _worldId.value) {
      throw StateError(
        'Callable world route mismatch: expected ${_worldId.value}.',
      );
    }
    return result;
  }
}

/// Lazily creates exactly one client set for each world.
final class WorldClientCache<T> {
  WorldClientCache(this._builder);

  final WorldClientBuilder<T> _builder;
  final Map<WorldId, T> _clients = {};

  T forWorld(WorldCatalogEntry world) {
    final worldId = WorldId(world.worldId);
    return _clients.putIfAbsent(worldId, () => _builder(world));
  }
}

/// Firebase SDK clients that must always point to the same world.
final class WorldFirebaseClients {
  const WorldFirebaseClients({
    required this.firestore,
    required this.callables,
    required this.storage,
  });

  final FirebaseFirestore firestore;
  final WorldFunctionsClient callables;
  final FirebaseStorage storage;
}

/// The only production adapter allowed to construct world-specific clients.
final class WorldFirebaseClientCache {
  WorldFirebaseClientCache({required FirebaseApp app, String? emulatorHost})
    : _clients = WorldClientCache<WorldFirebaseClients>(
        (world) => _createClients(app, world, emulatorHost),
      );

  final WorldClientCache<WorldFirebaseClients> _clients;

  WorldFirebaseClients forWorld(WorldCatalogEntry world) {
    return _clients.forWorld(world);
  }

  static WorldFirebaseClients _createClients(
    FirebaseApp app,
    WorldCatalogEntry world,
    String? emulatorHost,
  ) {
    final firestore = FirebaseFirestore.instanceFor(
      app: app,
      databaseId: world.databaseId,
    );
    final functions = FirebaseFunctions.instanceFor(
      app: app,
      region: world.functionsRegion,
    );
    final storage = FirebaseStorage.instanceFor(
      app: app,
      bucket: world.bucketName,
    );

    if (firestore.databaseId != world.databaseId) {
      throw StateError(
        'Firestore route mismatch for ${world.worldId}: '
        '${firestore.databaseId}',
      );
    }
    if (storage.bucket != world.bucketName) {
      throw StateError(
        'Storage route mismatch for ${world.worldId}: ${storage.bucket}',
      );
    }

    if (emulatorHost != null) {
      firestore.useFirestoreEmulator(emulatorHost, 8080);
      firestore.settings = const Settings(persistenceEnabled: false);
      functions.useFunctionsEmulator(emulatorHost, 5001);
      storage.useStorageEmulator(emulatorHost, 9199);
    }

    return WorldFirebaseClients(
      firestore: firestore,
      callables: WorldFunctionsClient(
        worldId: WorldId(world.worldId),
        functions: functions,
      ),
      storage: storage,
    );
  }
}
