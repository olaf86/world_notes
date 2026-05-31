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
  final String createdByUserId;
  final DateTime createdAt;
  final int messageCount;
  final DateTime? lastMessageAt;
  final PlaceVisibility visibility;
  final int passwordVersion;
  final bool isOpen;
  final ClosedReason? closedReason;
  final DateTime? closedAt;
  final bool isArchived;
  final DateTime? archivedAt;
  final DateTime expiresAt;

  PlaceModel({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.geohash,
    required this.title,
    this.subtitle,
    required this.colorHex,
    required this.icon,
    required this.createdByUserId,
    required this.createdAt,
    required this.expiresAt,
    this.messageCount = 0,
    this.lastMessageAt,
    this.visibility = PlaceVisibility.public,
    this.passwordVersion = 0,
    this.isOpen = true,
    this.closedReason,
    this.closedAt,
    this.isArchived = false,
    this.archivedAt,
  });

  factory PlaceModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PlaceModel(
      id: doc.id,
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      geohash: data['geohash'] as String,
      title: data['title'] as String,
      subtitle: data['subtitle'] as String?,
      colorHex: data['colorHex'] as String? ?? '#4CAF50',
      icon: data['icon'] as String? ?? 'place',
      createdByUserId: data['createdByUserId'] as String,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      messageCount: (data['messageCount'] as int?) ?? 0,
      lastMessageAt: (data['lastMessageAt'] as Timestamp?)?.toDate(),
      visibility: PlaceVisibility.fromJson(data['visibility'] as String?),
      passwordVersion: (data['passwordVersion'] as int?) ?? 0,
      isOpen: data['isOpen'] as bool? ?? true,
      closedReason: ClosedReason.fromJson(data['closedReason'] as String?),
      closedAt: (data['closedAt'] as Timestamp?)?.toDate(),
      isArchived: data['isArchived'] as bool? ?? false,
      archivedAt: (data['archivedAt'] as Timestamp?)?.toDate(),
      // expiresAt may be absent on legacy docs created before this field
      // existed — default to createdAt + 1 year so they still resolve.
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate() ??
          ((data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now())
              .add(const Duration(days: 365)),
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
      'createdByUserId': createdByUserId,
      'createdAt': FieldValue.serverTimestamp(),
      'messageCount': messageCount,
      'lastMessageAt': lastMessageAt != null
          ? Timestamp.fromDate(lastMessageAt!)
          : FieldValue.serverTimestamp(),
      'visibility': visibility.toJson(),
      'passwordVersion': passwordVersion,
      'isOpen': isOpen,
      if (closedReason != null) 'closedReason': closedReason!.toJson(),
      if (closedAt != null) 'closedAt': Timestamp.fromDate(closedAt!),
      'isArchived': isArchived,
      if (archivedAt != null) 'archivedAt': Timestamp.fromDate(archivedAt!),
      'expiresAt': Timestamp.fromDate(expiresAt),
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
        createdByUserId: createdByUserId,
        createdAt: createdAt,
        messageCount: messageCount,
        lastMessageAt: lastMessageAt,
        visibility: visibility,
        passwordVersion: passwordVersion,
        isOpen: isOpen,
        closedReason: closedReason,
        closedAt: closedAt,
        isArchived: isArchived,
        archivedAt: archivedAt,
        expiresAt: expiresAt,
      );
}
