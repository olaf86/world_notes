import 'world_catalog.dart';

const WorldId asiaWorldId = WorldId('asia');

/// Catalog bundled with the app until the trusted server projection is wired.
///
/// Keep this byte-for-byte equivalent to
/// `functions/src/platform/worldCatalog.config.json`. A contract test detects
/// drift between the two copies.
const Map<String, Object?> bootstrapWorldCatalogData = {
  'schemaVersion': 1,
  'catalogVersion': 3,
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
      'worldId': 'northAmerica',
      'databaseId': 'north-america',
      'firestoreLocation': 'us-central1',
      'functionsRegion': 'us-central1',
      'bucketName': 'world-notes-prod-north-america',
      'displayNameKey': 'world.northAmerica',
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

final WorldCatalog bootstrapWorldCatalog = WorldCatalog.fromJson(
  bootstrapWorldCatalogData,
);
