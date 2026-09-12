import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const inviteComponentPath = '/worlds/*/invites/*';
  const inviteHostingSource = '/worlds/*/invites/*';

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
      {'source': inviteHostingSource, 'destination': '/invite/index.html'},
    ]);

    final marketingPage = File('public/index.html').readAsStringSync();
    final invitationPage = File(
      'public/invite/index.html',
    ).readAsStringSync();

    expect(marketingPage, contains('思い出を、'));
    expect(marketingPage, contains('https://apps.apple.com/app/id6770728738'));
    expect(invitationPage, contains("You've been invited"));
  });
}
