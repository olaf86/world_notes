import 'dart:async';

import 'package:go_router/go_router.dart';

import 'world_catalog.dart';
import 'world_navigation.dart';
import 'world_routes.dart';

class NotificationPlaceRoute {
  final WorldRoute note;
  final bool readOnly;

  const NotificationPlaceRoute({required this.note, this.readOnly = false});

  String get placeId => note.entityId;

  String get location =>
      WorldNavigation(note.worldId).note(note.entityId, readOnly: readOnly);
}

final class NotificationMapNoteTarget {
  const NotificationMapNoteTarget({
    required this.worldId,
    required this.placeId,
    required this.latitude,
    required this.longitude,
    this.messageId,
  });

  final WorldId worldId;
  final String placeId;
  final double latitude;
  final double longitude;
  final String? messageId;
}

NotificationMapNoteTarget? notificationMapNoteTargetFromAction(
  String? route,
  Map<String, Object?> params,
) {
  if (route != 'mapNote') return null;
  final worldId = params['worldId'];
  final placeId = params['placeId'];
  final messageId = params['messageId'];
  final latitude = params['latitude'];
  final longitude = params['longitude'];
  if (worldId is! String ||
      worldId.isEmpty ||
      placeId is! String ||
      placeId.isEmpty ||
      latitude is! num ||
      longitude is! num) {
    return null;
  }
  return NotificationMapNoteTarget(
    worldId: WorldId(worldId),
    placeId: placeId,
    messageId: messageId is String && messageId.isNotEmpty ? messageId : null,
    latitude: latitude.toDouble(),
    longitude: longitude.toDouble(),
  );
}

void openNotificationPlace(GoRouter router, NotificationPlaceRoute? route) {
  if (route == null) return;

  unawaited(router.push<void>(route.location));
}

void openNotices(GoRouter router) {
  router.go('/notices');
}
