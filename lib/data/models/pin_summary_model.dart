import '../../domain/entities/pin_summary_entity.dart';
import '../../domain/entities/note_theme.dart';

class PinSummaryModel {
  final String placeId;
  final double latitude;
  final double longitude;
  final String title;
  final String? subtitle;
  final String colorHex;
  final NoteThemeId themeId;
  final String icon;
  final String? pinImageStoragePath;
  final String creatorName;
  final String? creatorPhotoUrl;
  final int creatorPhotoVersion;
  final int messageCount;
  final int likeCount;
  final int visitorCount;
  final DateTime createdAt;
  final DateTime lastActivityAt;
  final DateTime expiresAt;
  final bool isPrivate;
  final bool isClosed;
  final bool footprintEnabled;
  final PinAccess access;
  final Set<PinMarkerFlag> markerFlags;

  const PinSummaryModel({
    required this.placeId,
    required this.latitude,
    required this.longitude,
    required this.title,
    this.subtitle,
    required this.colorHex,
    required this.themeId,
    required this.icon,
    this.pinImageStoragePath,
    required this.creatorName,
    this.creatorPhotoUrl,
    required this.creatorPhotoVersion,
    required this.messageCount,
    required this.likeCount,
    required this.visitorCount,
    required this.createdAt,
    required this.lastActivityAt,
    required this.expiresAt,
    required this.isPrivate,
    required this.isClosed,
    required this.footprintEnabled,
    required this.access,
    this.markerFlags = const <PinMarkerFlag>{},
  });

  factory PinSummaryModel.fromJson(Map<String, dynamic> json) {
    final lastActivityAtMillis = json['lastActivityAtMillis'] as int;
    final createdAtMillis =
        (json['createdAtMillis'] as int?) ?? lastActivityAtMillis;

    return PinSummaryModel(
      placeId: json['placeId'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      title: json['title'] as String,
      subtitle: json['subtitle'] as String?,
      colorHex: json['colorHex'] as String,
      themeId: NoteThemeId.fromJson(json['themeId']),
      icon: json['icon'] as String,
      pinImageStoragePath: json['pinImageStoragePath'] as String?,
      creatorName: json['creatorName'] as String,
      creatorPhotoUrl: json['creatorPhotoUrl'] as String?,
      creatorPhotoVersion: json['creatorPhotoVersion'] as int,
      messageCount: json['messageCount'] as int,
      likeCount: json['likeCount'] as int,
      visitorCount: json['visitorCount'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMillis),
      lastActivityAt: DateTime.fromMillisecondsSinceEpoch(lastActivityAtMillis),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        json['expiresAtMillis'] as int,
      ),
      isPrivate: json['isPrivate'] as bool,
      isClosed: json['isClosed'] as bool,
      footprintEnabled: json['footprintEnabled'] as bool,
      access: PinAccess.fromJson(json['access'] as String?),
      markerFlags: _markerFlagsFromJson(json['markerFlags']),
    );
  }

  PinSummary toEntity() => PinSummary(
    placeId: placeId,
    latitude: latitude,
    longitude: longitude,
    title: title,
    subtitle: subtitle,
    colorHex: colorHex,
    themeId: themeId,
    icon: icon,
    pinImageStoragePath: pinImageStoragePath,
    creatorName: creatorName,
    creatorPhotoUrl: creatorPhotoUrl,
    creatorPhotoVersion: creatorPhotoVersion,
    messageCount: messageCount,
    likeCount: likeCount,
    visitorCount: visitorCount,
    createdAt: createdAt,
    lastActivityAt: lastActivityAt,
    expiresAt: expiresAt,
    isPrivate: isPrivate,
    isClosed: isClosed,
    footprintEnabled: footprintEnabled,
    access: access,
    markerFlags: markerFlags,
  );
}

Set<PinMarkerFlag> _markerFlagsFromJson(Object? value) {
  if (value is! List) return const <PinMarkerFlag>{};
  return value
      .whereType<String>()
      .map(PinMarkerFlag.fromJson)
      .whereType<PinMarkerFlag>()
      .toSet();
}
