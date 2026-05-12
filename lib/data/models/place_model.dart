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
      createdAt: (data['createdAt'] as Timestamp).toDate(),
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
      'createdAt': Timestamp.fromDate(createdAt),
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
      );
}
