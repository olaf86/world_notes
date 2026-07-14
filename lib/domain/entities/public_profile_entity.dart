class PublicProfile {
  final String id;
  final String displayName;
  final String? photoUrl;
  final int photoVersion;
  final int followerCount;
  final int followingCount;

  const PublicProfile({
    required this.id,
    required this.displayName,
    this.photoUrl,
    required this.photoVersion,
    this.followerCount = 0,
    this.followingCount = 0,
  });

  String get label {
    final trimmed = displayName.trim();
    return trimmed.isEmpty ? id : trimmed;
  }

  PublicProfile copyWith({
    String? id,
    String? displayName,
    String? photoUrl,
    int? photoVersion,
    int? followerCount,
    int? followingCount,
  }) {
    return PublicProfile(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      photoVersion: photoVersion ?? this.photoVersion,
      followerCount: followerCount ?? this.followerCount,
      followingCount: followingCount ?? this.followingCount,
    );
  }
}
