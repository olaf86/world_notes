import 'package:cloud_firestore/cloud_firestore.dart';

import '../../config/app_config.dart';
import '../../domain/entities/nearby_notification_entity.dart';

class NearbyNotificationModel {
  final String placeId;
  final String title;
  final String colorHex;
  final String icon;
  final double latitude;
  final double longitude;
  final int radiusMeters;
  final DateTime expiresAt;
  final bool enabled;
  final NearbyNotificationState state;
  final DateTime? lastReadMessageAt;
  final DateTime? lastNotifiedMessageAt;
  final bool inRange;
  final DateTime? inRangeUntil;
  final DateTime? updatedAt;

  const NearbyNotificationModel({
    required this.placeId,
    required this.title,
    required this.colorHex,
    required this.icon,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.expiresAt,
    required this.enabled,
    required this.state,
    this.lastReadMessageAt,
    this.lastNotifiedMessageAt,
    this.inRange = false,
    this.inRangeUntil,
    this.updatedAt,
  });

  factory NearbyNotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NearbyNotificationModel(
      placeId: data['placeId'] as String? ?? doc.id,
      title: data['title'] as String? ?? 'Untitled note',
      colorHex: data['colorHex'] as String,
      icon: data['icon'] as String,
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      radiusMeters:
          data['radiusMeters'] as int? ??
          AppConfig.nearbyNotificationRadiusMeters,
      expiresAt:
          (data['expiresAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      enabled: data['enabled'] as bool? ?? false,
      state: NearbyNotificationState.fromJson(data['state'] as String?),
      lastReadMessageAt: (data['lastReadMessageAt'] as Timestamp?)?.toDate(),
      lastNotifiedMessageAt: (data['lastNotifiedMessageAt'] as Timestamp?)
          ?.toDate(),
      inRange: data['inRange'] as bool? ?? false,
      inRangeUntil: (data['inRangeUntil'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  NearbyNotificationPlace toEntity() => NearbyNotificationPlace(
    placeId: placeId,
    title: title,
    colorHex: colorHex,
    icon: icon,
    latitude: latitude,
    longitude: longitude,
    radiusMeters: radiusMeters,
    expiresAt: expiresAt,
    enabled: enabled,
    state: state,
    lastReadMessageAt: lastReadMessageAt,
    lastNotifiedMessageAt: lastNotifiedMessageAt,
    inRange: inRange,
    inRangeUntil: inRangeUntil,
    updatedAt: updatedAt,
  );
}
