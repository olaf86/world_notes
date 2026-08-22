import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/config/bootstrap_world_catalog.dart';
import 'package:world_notes/config/world_catalog.dart';

void main() {
  late Map<String, Object?> sourceCatalog;

  setUp(() {
    sourceCatalog =
        jsonDecode(
              File(
                'functions/src/platform/worldCatalog.config.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
  });

  test('parses the server world catalog contract', () {
    final catalog = WorldCatalog.fromJson(sourceCatalog);

    expect(catalog.schemaVersion, 1);
    expect(catalog.catalogVersion, 5);
    expect(
      catalog.worlds
          .map((world) => (world.worldId, world.databaseId, world.catalogState))
          .toList(),
      [
        ('asia', '(default)', WorldCatalogState.homeEnabled),
        ('northAmerica', 'north-america', WorldCatalogState.homeEnabled),
        ('europe', 'europe', WorldCatalogState.homeEnabled),
      ],
    );
    expect(catalog.findWorld('europe')?.functionsRegion, 'europe-west1');
    expect(catalog.findWorld('unknown'), isNull);
  });

  test('bundled bootstrap catalog matches the server catalog', () {
    expect(bootstrapWorldCatalogData, sourceCatalog);
  });

  test('permits content routing only for enabled worlds', () {
    expect(
      bootstrapWorldCatalog.requireContentWorld(asiaWorldId).databaseId,
      '(default)',
    );
    expect(
      bootstrapWorldCatalog.requireHomeWorld(asiaWorldId).databaseId,
      '(default)',
    );
    expect(
      bootstrapWorldCatalog
          .requireContentWorld(const WorldId('northAmerica'))
          .databaseId,
      'north-america',
    );
    expect(
      bootstrapWorldCatalog
          .requireHomeWorld(const WorldId('northAmerica'))
          .databaseId,
      'north-america',
    );
    expect(
      bootstrapWorldCatalog
          .requireContentWorld(const WorldId('europe'))
          .databaseId,
      'europe',
    );
    expect(
      bootstrapWorldCatalog
          .requireHomeWorld(const WorldId('europe'))
          .databaseId,
      'europe',
    );
    expect(
      () => bootstrapWorldCatalog.requireContentWorld(const WorldId('unknown')),
      throwsStateError,
    );
  });

  test('rejects unknown and missing fields', () {
    final unknownField = _mutableClone(sourceCatalog)..['unexpected'] = true;
    expect(
      () => WorldCatalog.fromJson(unknownField),
      throwsA(isA<FormatException>()),
    );

    final missingField = _mutableClone(sourceCatalog);
    _worldAt(missingField, 0).remove('functionsRegion');
    expect(
      () => WorldCatalog.fromJson(missingField),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects duplicate routing resources', () {
    final duplicateWorld = _mutableClone(sourceCatalog);
    _worldAt(duplicateWorld, 1)['worldId'] = 'asia';
    expect(
      () => WorldCatalog.fromJson(duplicateWorld),
      throwsA(isA<FormatException>()),
    );

    final duplicateDatabase = _mutableClone(sourceCatalog);
    _worldAt(duplicateDatabase, 1)['databaseId'] = '(default)';
    expect(
      () => WorldCatalog.fromJson(duplicateDatabase),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects missing buckets and premature lifecycle flags', () {
    final missingBucket = _mutableClone(sourceCatalog);
    _worldAt(missingBucket, 1)['bucketName'] = null;
    expect(
      () => WorldCatalog.fromJson(missingBucket),
      throwsA(isA<FormatException>()),
    );

    final earlyContent = _mutableClone(sourceCatalog);
    _worldAt(earlyContent, 2)['catalogState'] = 'mirrorOnly';
    _worldAt(earlyContent, 2)['contentAccessEnabled'] = true;
    expect(
      () => WorldCatalog.fromJson(earlyContent),
      throwsA(isA<FormatException>()),
    );

    final earlyHome = _mutableClone(sourceCatalog);
    _worldAt(earlyHome, 0)['catalogState'] = 'contentEnabled';
    expect(
      () => WorldCatalog.fromJson(earlyHome),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects unsupported schema versions', () {
    final catalog = _mutableClone(sourceCatalog)..['schemaVersion'] = 2;

    expect(
      () => WorldCatalog.fromJson(catalog),
      throwsA(isA<FormatException>()),
    );
  });
}

Map<String, Object?> _mutableClone(Map<String, Object?> source) {
  return jsonDecode(jsonEncode(source)) as Map<String, Object?>;
}

Map<String, Object?> _worldAt(Map<String, Object?> catalog, int index) {
  final worlds = catalog['worlds']! as List<Object?>;
  return worlds[index] as Map<String, Object?>;
}
