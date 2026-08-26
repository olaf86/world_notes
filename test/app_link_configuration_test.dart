import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const inviteComponentPath = '/worlds/*/invites/*';
  const inviteHostingSource = '/worlds/:worldId/invites/:token';

  test('AASA exposes only the canonical world invitation path', () {
    final aasa =
        jsonDecode(
              File(
                'public/.well-known/apple-app-site-association',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final applinks = aasa['applinks'] as Map<String, dynamic>;
    final details = applinks['details'] as List<dynamic>;

    expect(details, hasLength(1));
    final detail = details.single as Map<String, dynamic>;
    expect(detail['appIDs'], ['48C76HC76Y.dev.asobo.worldnotes']);
    expect(detail['components'], [
      {'/': inviteComponentPath, 'comment': 'Private-note invite links'},
    ]);
  });

  test('Firebase Hosting serves the canonical invitation fallback page', () {
    final firebase =
        jsonDecode(File('firebase.json').readAsStringSync())
            as Map<String, dynamic>;
    final hosting = firebase['hosting'] as Map<String, dynamic>;

    expect(hosting['rewrites'], [
      {'source': inviteHostingSource, 'destination': '/index.html'},
    ]);
  });
}
