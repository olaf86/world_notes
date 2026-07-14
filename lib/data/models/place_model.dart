import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/place_entity.dart';

class PlaceModel {
  final String id;
  final double latitude;
  final double longitude;
  final String geohash;
  final String title;
  final String? subtitle;
  final String colorHex;
  final String icon;
  final String? pinImageStoragePath;
  final String createdByUserId;
  final String creatorName;
  final String? creatorPhotoUrl;
  final int creatorPhotoVersion;
  final List<String> maintainerIds;
  final DateTime createdAt;
  final DateTime publishAt;
  final int messageCount;
  final int likeCount;
  final DateTime? lastMessageAt;
  final PlaceVisibility visibility;
  final int passwordVersion;
  final NoteLockType? lockType;
  final String? lockHint;
  final bool isOpen;
  final ClosedReason? closedReason;
  final DateTime? closedAt;
  final bool isArchived;
  final DateTime? archivedAt;
  final DateTime expiresAt;
  final bool footprintEnabled;
  final int visitorCount;

  PlaceModel({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.geohash,
    required this.title,
    this.subtitle,
    required this.colorHex,
    required this.icon,
    this.pinImageStoragePath,
    required this.createdByUserId,
    required this.creatorName,
    this.creatorPhotoUrl,
    required this.creatorPhotoVersion,
    this.maintainerIds = const [],
    required this.createdAt,
    required this.publishAt,
    required this.expiresAt,
    this.messageCount = 0,
    required this.likeCount,
    this.lastMessageAt,
    this.visibility = PlaceVisibility.public,
    this.passwordVersion = 0,
    this.lockType,
    this.lockHint,
    this.isOpen = true,
    this.closedReason,
    this.closedAt,
    this.isArchived = false,
    this.archivedAt,
    this.footprintEnabled = true,
    this.visitorCount = 0,
  });

  static List<String> _maintainerIdsFromData(Map<String, dynamic> data) {
    final createdByUserId = data['createdByUserId'] as String;
    final maintainerIds = (data['maintainerIds'] as List<dynamic>?)
        ?.whereType<String>()
        .toList();
    if (maintainerIds == null || maintainerIds.isEmpty) {
      return [createdByUserId];
    }
    if (maintainerIds.contains(createdByUserId)) return maintainerIds;
    return [createdByUserId, ...maintainerIds];
  }

  factory PlaceModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PlaceModel(
      id: doc.id,
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      geohash: data['geohash'] as String,
      title: data['title'] as String,
      subtitle: data['subtitle'] as String?,
      colorHex: data['colorHex'] as String,
      icon: data['icon'] as String,
      pinImageStoragePath: data['pinImageStoragePath'] as String?,
      createdByUserId: data['createdByUserId'] as String,
      creatorName: data['creatorName'] as String,
      creatorPhotoUrl: data['creatorPhotoUrl'] as String?,
      creatorPhotoVersion: data['creatorPhotoVersion'] as int,
      maintainerIds: _maintainerIdsFromData(data),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      publishAt: (data['publishAt'] as Timestamp).toDate(),
      messageCount: data['messageCount'] as int,
      likeCount: data['likeCount'] as int,
      lastMessageAt: (data['lastMessageAt'] as Timestamp?)?.toDate(),
      visibility: PlaceVisibility.fromJson(data['visibility'] as String),
      passwordVersion: data['passwordVersion'] as int,
      lockType: NoteLockType.fromJson(data['lockType'] as String?),
      lockHint: data['lockHint'] as String?,
      isOpen: data['isOpen'] as bool,
      closedReason: ClosedReason.fromJson(data['closedReason'] as String?),
      closedAt: (data['closedAt'] as Timestamp?)?.toDate(),
      isArchived: data['isArchived'] as bool,
      archivedAt: (data['archivedAt'] as Timestamp?)?.toDate(),
      expiresAt: (data['expiresAt'] as Timestamp).toDate(),
      footprintEnabled: data['footprintEnabled'] as bool? ?? true,
      visitorCount: data['visitorCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'geohash': geohash,
      'title': title,
      'subtitle': subtitle,
      'colorHex': colorHex,
      'icon': icon,
      if (pinImageStoragePath != null)
        'pinImageStoragePath': pinImageStoragePath,
      'createdByUserId': createdByUserId,
      'creatorName': creatorName,
      if (creatorPhotoUrl != null) 'creatorPhotoUrl': creatorPhotoUrl,
      'creatorPhotoVersion': creatorPhotoVersion,
      'maintainerIds': maintainerIds.isEmpty
          ? [createdByUserId]
          : maintainerIds,
      'createdAt': FieldValue.serverTimestamp(),
      'publishAt': Timestamp.fromDate(publishAt),
      'messageCount': messageCount,
      'likeCount': likeCount,
      'lastMessageAt': lastMessageAt != null
          ? Timestamp.fromDate(lastMessageAt!)
          : FieldValue.serverTimestamp(),
      'visibility': visibility.toJson(),
      'passwordVersion': passwordVersion,
      if (lockType != null) 'lockType': lockType!.toJson(),
      if (lockHint != null) 'lockHint': lockHint,
      'isOpen': isOpen,
      if (closedReason != null) 'closedReason': closedReason!.toJson(),
      if (closedAt != null) 'closedAt': Timestamp.fromDate(closedAt!),
      'isArchived': isArchived,
      if (archivedAt != null) 'archivedAt': Timestamp.fromDate(archivedAt!),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'footprintEnabled': footprintEnabled,
      'visitorCount': visitorCount,
    };
  }

  PlaceEntity toEntity() => PlaceEntity(
    id: id,
    latitude: latitude,
    longitude: longitude,
    geohash: geohash,
    title: title,
    subtitle: subtitle,
    colorHex: colorHex,
    icon: icon,
    pinImageStoragePath: pinImageStoragePath,
    createdByUserId: createdByUserId,
    creatorName: creatorName,
    creatorPhotoUrl: creatorPhotoUrl,
    creatorPhotoVersion: creatorPhotoVersion,
    maintainerIds: maintainerIds,
    createdAt: createdAt,
    publishAt: publishAt,
    messageCount: messageCount,
    likeCount: likeCount,
    lastMessageAt: lastMessageAt,
    visibility: visibility,
    passwordVersion: passwordVersion,
    lockType: lockType,
    lockHint: lockHint,
    isOpen: isOpen,
    closedReason: closedReason,
    closedAt: closedAt,
    isArchived: isArchived,
    archivedAt: archivedAt,
    expiresAt: expiresAt,
    footprintEnabled: footprintEnabled,
    visitorCount: visitorCount,
  );
}
