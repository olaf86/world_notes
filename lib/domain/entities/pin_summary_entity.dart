enum PinAccess {
  openable,
  distanceLocked;

  static PinAccess fromJson(String? value) => switch (value) {
    'openable' => openable,
    _ => distanceLocked,
  };
}

class PinSummary {
  final String placeId;
  final double latitude;
  final double longitude;
  final String title;
  final String? subtitle;
  final String colorHex;
  final String icon;
  final String? pinImageStoragePath;
  final String creatorName;
  final int messageCount;
  final DateTime createdAt;
  final DateTime lastActivityAt;
  final DateTime expiresAt;
  final bool isPrivate;
  final bool isClosed;
  final PinAccess access;

  const PinSummary({
    required this.placeId,
    required this.latitude,
    required this.longitude,
    required this.title,
    this.subtitle,
    required this.colorHex,
    required this.icon,
    this.pinImageStoragePath,
    required this.creatorName,
    required this.messageCount,
    required this.createdAt,
    required this.lastActivityAt,
    required this.expiresAt,
    required this.isPrivate,
    required this.isClosed,
    required this.access,
  });

  bool get canOpen => access == PinAccess.openable;
}
