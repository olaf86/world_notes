import 'dart:async';

import 'package:go_router/go_router.dart';

import 'world_routes.dart';

class NotificationPlaceRoute {
  final WorldRoute note;
  final bool readOnly;

  const NotificationPlaceRoute({required this.note, this.readOnly = false});

  String get placeId => note.entityId;

  String get location {
    return Uri(
      path: worldNotePath(note),
      queryParameters: readOnly ? const {'readOnly': 'true'} : null,
    ).toString();
  }
}

void openNotificationPlace(GoRouter router, NotificationPlaceRoute? route) {
  if (route == null) return;

  unawaited(router.push<void>(route.location));
}

void openNotices(GoRouter router) {
  router.go('/notices');
}
