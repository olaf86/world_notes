class PlaceEntity {
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

  const PlaceEntity({
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
  });
}
