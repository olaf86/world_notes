import 'note_theme.dart';

enum PinAccess {
  openable,
  distanceLocked;

  static PinAccess fromJson(String? value) => switch (value) {
    'openable' => openable,
    _ => distanceLocked,
  };
}

enum PinMarkerFlag {
  followedAuthorNew,
  unseenMessages;

  static PinMarkerFlag? fromJson(String value) => switch (value) {
    'followedAuthorNew' => followedAuthorNew,
    'unseenMessages' => unseenMessages,
    _ => null,
  };
}

class PinSummary {
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

  const PinSummary({
    required this.placeId,
    required this.latitude,
    required this.longitude,
    required this.title,
    this.subtitle,
    required this.colorHex,
    this.themeId = NoteThemeId.standard,
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

  bool get canOpen => access == PinAccess.openable;
  bool get isFromFollowedAuthor =>
      markerFlags.contains(PinMarkerFlag.followedAuthorNew);
  bool get hasUnseenMessages =>
      markerFlags.contains(PinMarkerFlag.unseenMessages);
  String get markerVariantKey {
    final names = markerFlags.map((flag) => flag.name).toList()..sort();
    return names.isEmpty ? 'normal' : names.join('_');
  }
}
