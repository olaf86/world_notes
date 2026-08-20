import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, dynamic> firebaseConfig;
  late List<Map<String, dynamic>> worlds;

  setUpAll(() {
    firebaseConfig =
        jsonDecode(File('firebase.json').readAsStringSync())
            as Map<String, dynamic>;
    final catalog =
        jsonDecode(
              File(
                'functions/src/platform/worldCatalog.config.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    worlds = (catalog['worlds'] as List<dynamic>).cast<Map<String, dynamic>>();
  });

  test('maps all world databases to the shared index contract', () {
    final firestore = (firebaseConfig['firestore'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    expect(
      {
        for (final database in firestore)
          database['database'] as String: database['indexes'] as String,
      },
      <String, String>{
        '(default)': 'firestore.indexes.json',
        'north-america': 'firestore.indexes.json',
        'europe': 'firestore.indexes.json',
      },
    );
  });

  test('maps Firestore rules to each world activation state', () {
    final firestore = (firebaseConfig['firestore'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    expect(
      {
        for (final database in firestore)
          database['database'] as String: database['rules'] as String,
      },
      <String, String>{
        for (final world in worlds)
          world['databaseId'] as String: world['contentAccessEnabled'] == true
              ? 'firestore.rules'
              : 'firestore.named.locked.rules',
      },
    );
  });

  test('maps Storage rules to each world activation state', () {
    final storage = (firebaseConfig['storage'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final firebaseRc =
        jsonDecode(File('.firebaserc').readAsStringSync())
            as Map<String, dynamic>;
    final projects = firebaseRc['projects'] as Map<String, dynamic>;
    final projectId = projects['default'] as String;
    final targets = firebaseRc['targets'] as Map<String, dynamic>;
    final projectTargets = targets[projectId] as Map<String, dynamic>;
    final storageTargets = projectTargets['storage'] as Map<String, dynamic>;

    expect(
      {
        for (final bucket in storage)
          (storageTargets[bucket['target']] as List<dynamic>).single as String:
              bucket['rules'] as String,
      },
      <String, String>{
        for (final world in worlds)
          world['bucketName'] as String: world['contentAccessEnabled'] == true
              ? 'storage.rules'
              : 'storage.named.locked.rules',
      },
    );
  });
}
