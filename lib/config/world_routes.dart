import 'world_catalog.dart';

/// Stable address for regional data that may leave its Firestore database.
final class WorldRoute {
  WorldRoute({required this.worldId, required this.entityId}) {
    _requirePathSegment(worldId.value, 'worldId');
    _requirePathSegment(entityId, 'entityId');
  }

  final WorldId worldId;
  final String entityId;

  String get persistentId => '${worldId.value}:$entityId';

  @override
  bool operator ==(Object other) {
    return other is WorldRoute &&
        other.worldId == worldId &&
        other.entityId == entityId;
  }

  @override
  int get hashCode => Object.hash(worldId, entityId);
}

/// Stable address for a globally mirrored entity and its authority world.
final class GlobalEntityRoute {
  GlobalEntityRoute({
    required this.authorityWorld,
    required this.entityType,
    required this.entityId,
  }) {
    _requirePathSegment(authorityWorld.value, 'authorityWorld');
    _requirePathSegment(entityType, 'entityType');
    _requirePathSegment(entityId, 'entityId');
  }

  final WorldId authorityWorld;
  final String entityType;
  final String entityId;

  String get persistentId => '${authorityWorld.value}:$entityType:$entityId';
}

String worldNotePath(WorldRoute note) {
  return '/worlds/${note.worldId.value}/notes/${note.entityId}';
}

String worldNoteCreationPath(WorldId worldId) {
  return '/worlds/${worldId.value}/notes/create';
}

String worldInvitePath({required WorldId worldId, required String token}) {
  _requirePathSegment(token, 'token');
  return '/worlds/${worldId.value}/invites/$token';
}

void _requirePathSegment(String value, String name) {
  if (value.isEmpty || value.trim() != value || value.contains('/')) {
    throw ArgumentError.value(
      value,
      name,
      'Must be one non-empty path segment.',
    );
  }
}
