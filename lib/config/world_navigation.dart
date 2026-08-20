import 'app_config.dart';
import 'world_catalog.dart';
import 'world_routes.dart';

/// Builds canonical client routes for one content world.
///
/// UI code receives this through `selectedWorldNavigationProvider`, so normal
/// in-world navigation only supplies local entity IDs. External routes still
/// carry an explicit [WorldRoute].
final class WorldNavigation {
  const WorldNavigation(this.worldId);

  final WorldId worldId;

  String note(String placeId, {String? title, bool readOnly = false}) {
    final route = WorldRoute(worldId: worldId, entityId: placeId);
    final query = <String, String>{
      if (title != null && title.isNotEmpty) 'title': title,
      if (readOnly) 'readOnly': 'true',
    };
    return Uri(
      path: '/worlds/${route.worldId.value}/notes/${route.entityId}',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  String get noteCreation => '/worlds/${worldId.value}/notes/create';

  String noteReport(String placeId) => '${note(placeId)}/report';

  String messageReport(String placeId, String messageId) {
    final message = WorldRoute(worldId: worldId, entityId: messageId);
    return '${note(placeId)}/messages/${message.entityId}/report';
  }

  String noteVisitors(String placeId) => '${note(placeId)}/visitors';

  String invite(String token) {
    final invite = WorldRoute(worldId: worldId, entityId: token);
    return '/worlds/${invite.worldId.value}/invites/${invite.entityId}';
  }

  String inviteUrl(String token) =>
      '${AppConfig.inviteLinkBase}${invite(token)}';
}
