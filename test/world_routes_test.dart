import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/config/world_catalog.dart';
import 'package:world_notes/config/world_navigation.dart';
import 'package:world_notes/config/world_routes.dart';

void main() {
  test('world route keeps a regional entity globally unambiguous', () {
    final route = WorldRoute(
      worldId: const WorldId('europe'),
      entityId: 'note-42',
    );

    expect(route.persistentId, 'europe:note-42');
    expect(
      WorldNavigation(route.worldId).note(route.entityId),
      '/worlds/europe/notes/note-42',
    );
  });

  test('world route rejects values that cannot be one path segment', () {
    expect(
      () =>
          WorldRoute(worldId: const WorldId('asia'), entityId: 'notes/note-42'),
      throwsArgumentError,
    );
  });

  test('invite URLs include the data world', () {
    const navigation = WorldNavigation(WorldId('northAmerica'));

    expect(
      navigation.invite('invite-1'),
      '/worlds/northAmerica/invites/invite-1',
    );
    expect(
      navigation.inviteUrl('invite-1'),
      'https://worldnotes.asobo.dev/worlds/northAmerica/invites/invite-1',
    );
  });

  test('selected-world navigation supplies the world for normal UI routes', () {
    const navigation = WorldNavigation(WorldId('asia'));

    expect(
      navigation.note('note-1', title: 'Tokyo note', readOnly: true),
      '/worlds/asia/notes/note-1?title=Tokyo+note&readOnly=true',
    );
    expect(navigation.noteCreation, '/worlds/asia/notes/create');
    expect(
      navigation.messageReport('note-1', 'message-1'),
      '/worlds/asia/notes/note-1/messages/message-1/report',
    );
    expect(
      navigation.noteVisitors('note-1'),
      '/worlds/asia/notes/note-1/visitors',
    );
  });
}
