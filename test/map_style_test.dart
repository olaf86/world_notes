import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/core/map_style.dart';

void main() {
  test('standard Google map style uses the SDK default', () {
    expect(MapStyle.standard.googleMapStyleJson, isNull);
  });

  test('custom Google map styles contain valid client-side JSON', () {
    for (final style in [MapStyle.dark, MapStyle.pop]) {
      final decoded = jsonDecode(style.googleMapStyleJson!);
      expect(decoded, isA<List<dynamic>>(), reason: style.name);
      expect(decoded, isNotEmpty, reason: style.name);
    }
  });
}
