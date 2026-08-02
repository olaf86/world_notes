import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defines archived-note indexes for both sort directions', () {
    final config =
        jsonDecode(File('firestore.indexes.json').readAsStringSync())
            as Map<String, dynamic>;
    final indexes = config['indexes'] as List<dynamic>;

    final archivedAtDirections = <String>{
      for (final rawIndex in indexes)
        if (_isArchivedNotesIndex(rawIndex as Map<String, dynamic>))
          _orderOf(rawIndex, 'archivedAt')!,
    };

    expect(
      archivedAtDirections,
      containsAll(<String>{'ASCENDING', 'DESCENDING'}),
    );
  });

  test('defines the note-report resolution index', () {
    final config =
        jsonDecode(File('firestore.indexes.json').readAsStringSync())
            as Map<String, dynamic>;
    final indexes = config['indexes'] as List<dynamic>;

    expect(
      indexes.cast<Map<String, dynamic>>().any((index) {
        if (index['collectionGroup'] != 'reports') return false;
        final fields = (index['fields'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final paths = fields.map((field) => field['fieldPath']).toList();
        return paths.join(',') == 'targetType,targetId,status';
      }),
      isTrue,
    );
  });

  test('defines the pending global-operation reconciliation index', () {
    final config =
        jsonDecode(File('firestore.indexes.json').readAsStringSync())
            as Map<String, dynamic>;
    final indexes = (config['indexes'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    expect(
      indexes.any((index) {
        if (index['collectionGroup'] != 'globalOperations' ||
            index['queryScope'] != 'COLLECTION') {
          return false;
        }
        final fields = (index['fields'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        return fields.length == 2 &&
            fields[0]['fieldPath'] == 'status' &&
            fields[0]['order'] == 'ASCENDING' &&
            fields[1]['fieldPath'] == 'acceptedAt' &&
            fields[1]['order'] == 'ASCENDING';
      }),
      isTrue,
    );
  });

  test('defines due and expired-lease cleanup reconciliation indexes', () {
    final config =
        jsonDecode(File('firestore.indexes.json').readAsStringSync())
            as Map<String, dynamic>;
    final indexes = (config['indexes'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final secondFields = <String>{
      for (final index in indexes)
        if (index['collectionGroup'] == 'jobs' &&
            index['queryScope'] == 'COLLECTION' &&
            (index['fields'] as List<dynamic>).length == 2 &&
            ((index['fields'] as List<dynamic>)[0]
                    as Map<String, dynamic>)['fieldPath'] ==
                'status')
          ((index['fields'] as List<dynamic>)[1]
                  as Map<String, dynamic>)['fieldPath']
              as String,
    };

    expect(secondFields, containsAll(<String>{'nextAttemptAt', 'leaseUntil'}));
  });

  test('enables cleanup completion TTL without indexing its timestamp', () {
    final config =
        jsonDecode(File('firestore.indexes.json').readAsStringSync())
            as Map<String, dynamic>;
    final overrides = (config['fieldOverrides'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    expect(
      overrides.any(
        (override) =>
            override['collectionGroup'] == 'jobs' &&
            override['fieldPath'] == 'expireAt' &&
            override['ttl'] == true &&
            (override['indexes'] as List<dynamic>).isEmpty,
      ),
      isTrue,
    );
  });
}

bool _isArchivedNotesIndex(Map<String, dynamic> index) {
  if (index['collectionGroup'] != 'places' ||
      index['queryScope'] != 'COLLECTION') {
    return false;
  }

  final fields = (index['fields'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  return fields.any(
        (field) =>
            field['fieldPath'] == 'maintainerIds' &&
            field['arrayConfig'] == 'CONTAINS',
      ) &&
      fields.any(
        (field) =>
            field['fieldPath'] == 'isArchived' && field['order'] == 'ASCENDING',
      ) &&
      _orderOf(index, 'archivedAt') != null;
}

String? _orderOf(Map<String, dynamic> index, String fieldPath) {
  for (final field
      in (index['fields'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    if (field['fieldPath'] == fieldPath) return field['order'] as String?;
  }
  return null;
}
