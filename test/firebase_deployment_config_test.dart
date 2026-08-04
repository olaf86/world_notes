import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps all world databases to the shared index contract', () {
    final config =
        jsonDecode(File('firebase.json').readAsStringSync())
            as Map<String, dynamic>;
    final firestore = (config['firestore'] as List<dynamic>)
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

  test('keeps mirror-only named databases locked to client traffic', () {
    final config =
        jsonDecode(File('firebase.json').readAsStringSync())
            as Map<String, dynamic>;
    final firestore = (config['firestore'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    expect(
      {
        for (final database in firestore)
          database['database'] as String: database['rules'] as String,
      },
      <String, String>{
        '(default)': 'firestore.rules',
        'north-america': 'firestore.named.locked.rules',
        'europe': 'firestore.named.locked.rules',
      },
    );
  });
}
