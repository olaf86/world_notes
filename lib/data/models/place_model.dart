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
  final PlaceStatus status;
  final DateTime? closedAt;
  final DateTime? archivedAt;
  final bool isLocked;
  final String? passwordHash;

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
    this.messageCount = 0,
    this.lastMessageAt,
    this.status = PlaceStatus.active,
    this.closedAt,
    this.archivedAt,
    this.isLocked = false,
    this.passwordHash,
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
      status: PlaceStatus.fromJson(data['status'] as String?),
      closedAt: (data['closedAt'] as Timestamp?)?.toDate(),
      archivedAt: (data['archivedAt'] as Timestamp?)?.toDate(),
      isLocked: data['isLocked'] as bool? ?? false,
      passwordHash: data['passwordHash'] as String?,
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
      'status': status.toJson(),
      if (closedAt != null) 'closedAt': Timestamp.fromDate(closedAt!),
      if (archivedAt != null) 'archivedAt': Timestamp.fromDate(archivedAt!),
      'isLocked': isLocked,
      if (passwordHash != null) 'passwordHash': passwordHash,
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
        status: status,
        closedAt: closedAt,
        archivedAt: archivedAt,
        isLocked: isLocked,
        passwordHash: passwordHash,
      );
}
