import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/config/world_catalog.dart';
import 'package:world_notes/config/world_routes.dart';

void main() {
  test('world route keeps a regional entity globally unambiguous', () {
    final route = WorldRoute(
      worldId: const WorldId('europe'),
      entityId: 'note-42',
    );

    expect(route.persistentId, 'europe:note-42');
    expect(worldNotePath(route), '/worlds/europe/notes/note-42');
  });

  test('world route rejects values that cannot be one path segment', () {
    expect(
      () =>
          WorldRoute(worldId: const WorldId('asia'), entityId: 'notes/note-42'),
      throwsArgumentError,
    );
  });

  test('invite URLs include the data world', () {
    expect(
      worldInvitePath(
        worldId: const WorldId('northAmerica'),
        token: 'invite-1',
      ),
      '/worlds/northAmerica/invites/invite-1',
    );
  });
}
