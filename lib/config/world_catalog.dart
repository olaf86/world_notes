/// Wire schema version supported by this client.
const int worldCatalogSchemaVersion = 1;

/// Provisioning lifecycle for a world and its regional resources.
enum WorldCatalogState {
  provisioning('provisioning'),
  mirrorOnly('mirrorOnly'),
  contentEnabled('contentEnabled'),
  homeEnabled('homeEnabled');

  const WorldCatalogState(this.wireValue);

  final String wireValue;

  static WorldCatalogState parse(Object? value, String path) {
    for (final state in values) {
      if (state.wireValue == value) return state;
    }
    throw FormatException('$path is unsupported.');
  }
}

/// Validated routing and activation metadata for one world.
class WorldCatalogEntry {
  const WorldCatalogEntry({
    required this.worldId,
    required this.databaseId,
    required this.firestoreLocation,
    required this.functionsRegion,
    required this.bucketName,
    required this.displayNameKey,
    required this.catalogState,
    required this.homeAssignmentEnabled,
    required this.contentAccessEnabled,
  });

  final String worldId;
  final String databaseId;
  final String firestoreLocation;
  final String functionsRegion;
  final String? bucketName;
  final String displayNameKey;
  final WorldCatalogState catalogState;
  final bool homeAssignmentEnabled;
  final bool contentAccessEnabled;

  factory WorldCatalogEntry.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    _requireExactKeys(json, _worldKeys, path);

    final entry = WorldCatalogEntry(
      worldId: _requirePatternedString(
        json['worldId'],
        '$path.worldId',
        _worldIdPattern,
      ),
      databaseId: _requireDatabaseId(json['databaseId'], '$path.databaseId'),
      firestoreLocation: _requirePatternedString(
        json['firestoreLocation'],
        '$path.firestoreLocation',
        _regionPattern,
      ),
      functionsRegion: _requirePatternedString(
        json['functionsRegion'],
        '$path.functionsRegion',
        _regionPattern,
      ),
      bucketName: _requireNullableBucketName(
        json['bucketName'],
        '$path.bucketName',
      ),
      displayNameKey: _requirePatternedString(
        json['displayNameKey'],
        '$path.displayNameKey',
        _displayNameKeyPattern,
      ),
      catalogState: WorldCatalogState.parse(
        json['catalogState'],
        '$path.catalogState',
      ),
      homeAssignmentEnabled: _requireBool(
        json['homeAssignmentEnabled'],
        '$path.homeAssignmentEnabled',
      ),
      contentAccessEnabled: _requireBool(
        json['contentAccessEnabled'],
        '$path.contentAccessEnabled',
      ),
    );
    entry._validateLifecycle(path);
    return entry;
  }

  void _validateLifecycle(String path) {
    if (catalogState != WorldCatalogState.provisioning && bucketName == null) {
      throw FormatException('$path.bucketName is required after provisioning.');
    }
    if (contentAccessEnabled &&
        catalogState != WorldCatalogState.contentEnabled &&
        catalogState != WorldCatalogState.homeEnabled) {
      throw FormatException(
        '$path.contentAccessEnabled requires an enabled state.',
      );
    }
    if (homeAssignmentEnabled &&
        catalogState != WorldCatalogState.homeEnabled) {
      throw FormatException(
        '$path.homeAssignmentEnabled requires homeEnabled state.',
      );
    }
    if (homeAssignmentEnabled && !contentAccessEnabled) {
      throw FormatException(
        '$path.homeAssignmentEnabled requires content access.',
      );
    }
  }
}

/// Versioned world catalog received from the trusted server.
class WorldCatalog {
  const WorldCatalog({
    required this.schemaVersion,
    required this.catalogVersion,
    required this.worlds,
  });

  final int schemaVersion;
  final int catalogVersion;
  final List<WorldCatalogEntry> worlds;

  factory WorldCatalog.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, _catalogKeys, 'catalog');

    final schemaVersion = _requirePositiveInt(
      json['schemaVersion'],
      'catalog.schemaVersion',
    );
    if (schemaVersion != worldCatalogSchemaVersion) {
      throw FormatException(
        'catalog.schemaVersion must be $worldCatalogSchemaVersion; '
        'received $schemaVersion.',
      );
    }
    final catalogVersion = _requirePositiveInt(
      json['catalogVersion'],
      'catalog.catalogVersion',
    );
    final rawWorlds = json['worlds'];
    if (rawWorlds is! List<Object?> || rawWorlds.isEmpty) {
      throw const FormatException('catalog.worlds must be a non-empty array.');
    }

    final worlds = List<WorldCatalogEntry>.unmodifiable(
      rawWorlds.indexed.map(
        (indexedWorld) => WorldCatalogEntry.fromJson(
          _requireObject(indexedWorld.$2, 'catalog.worlds[${indexedWorld.$1}]'),
          path: 'catalog.worlds[${indexedWorld.$1}]',
        ),
      ),
    );
    _validateUniqueRoutes(worlds);
    return WorldCatalog(
      schemaVersion: schemaVersion,
      catalogVersion: catalogVersion,
      worlds: worlds,
    );
  }

  WorldCatalogEntry? findWorld(String worldId) {
    for (final world in worlds) {
      if (world.worldId == worldId) return world;
    }
    return null;
  }
}

const _catalogKeys = {'schemaVersion', 'catalogVersion', 'worlds'};
const _worldKeys = {
  'worldId',
  'databaseId',
  'firestoreLocation',
  'functionsRegion',
  'bucketName',
  'displayNameKey',
  'catalogState',
  'homeAssignmentEnabled',
  'contentAccessEnabled',
};
final _worldIdPattern = RegExp(r'^[a-z][A-Za-z0-9]{1,31}$');
final _databaseIdPattern = RegExp(r'^[a-z][a-z0-9-]{2,61}[a-z0-9]$');
final _regionPattern = RegExp(r'^[a-z]+(?:-[a-z0-9]+)+[0-9]$');
final _bucketNamePattern = RegExp(r'^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$');
final _displayNameKeyPattern = RegExp(r'^world\.[a-z][A-Za-z0-9]*$');

void _validateUniqueRoutes(List<WorldCatalogEntry> worlds) {
  final worldIds = <String>{};
  final databaseIds = <String>{};
  final bucketNames = <String>{};

  for (final world in worlds) {
    _requireUnique(worldIds, world.worldId, 'worldId');
    _requireUnique(databaseIds, world.databaseId, 'databaseId');
    final bucketName = world.bucketName;
    if (bucketName != null) {
      _requireUnique(bucketNames, bucketName, 'bucketName');
    }
  }
  if (!databaseIds.contains('(default)')) {
    throw const FormatException(
      'catalog.worlds must contain the (default) database.',
    );
  }
}

Map<String, Object?> _requireObject(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object.');
  }
  return value;
}

void _requireExactKeys(
  Map<String, Object?> json,
  Set<String> expectedKeys,
  String path,
) {
  final actualKeys = json.keys.toSet();
  final missing = expectedKeys.difference(actualKeys);
  final unknown = actualKeys.difference(expectedKeys);
  if (missing.isNotEmpty || unknown.isNotEmpty) {
    throw FormatException(
      '$path fields are invalid; missing=$missing, unknown=$unknown.',
    );
  }
}

int _requirePositiveInt(Object? value, String path) {
  if (value is! int || value <= 0) {
    throw FormatException('$path must be a positive integer.');
  }
  return value;
}

String _requirePatternedString(Object? value, String path, RegExp pattern) {
  if (value is! String || !pattern.hasMatch(value)) {
    throw FormatException('$path has an invalid format.');
  }
  return value;
}

String _requireDatabaseId(Object? value, String path) {
  if (value == '(default)') return '(default)';
  return _requirePatternedString(value, path, _databaseIdPattern);
}

String? _requireNullableBucketName(Object? value, String path) {
  if (value == null) return null;
  return _requirePatternedString(value, path, _bucketNamePattern);
}

bool _requireBool(Object? value, String path) {
  if (value is! bool) {
    throw FormatException('$path must be a boolean.');
  }
  return value;
}

void _requireUnique(Set<String> values, String value, String fieldName) {
  if (!values.add(value)) {
    throw FormatException('Duplicate $fieldName: $value');
  }
}
