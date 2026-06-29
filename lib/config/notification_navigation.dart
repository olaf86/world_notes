import 'dart:async';

import 'package:go_router/go_router.dart';

class NotificationPlaceRoute {
  final String placeId;
  final bool readOnly;

  const NotificationPlaceRoute({required this.placeId, this.readOnly = false});

  String get location {
    return Uri(
      path: '/note/$placeId',
      queryParameters: readOnly ? const {'readOnly': 'true'} : null,
    ).toString();
  }
}

void openNotificationPlace(GoRouter router, NotificationPlaceRoute? route) {
  if (route == null || route.placeId.isEmpty) return;

  unawaited(router.push<void>(route.location));
}
