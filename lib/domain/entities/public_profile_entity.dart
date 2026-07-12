class PublicProfile {
  final String id;
  final String displayName;
  final String? photoUrl;
  final int followerCount;
  final int followingCount;

  const PublicProfile({
    required this.id,
    required this.displayName,
    this.photoUrl,
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
    int? followerCount,
    int? followingCount,
  }) {
    return PublicProfile(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      followerCount: followerCount ?? this.followerCount,
      followingCount: followingCount ?? this.followingCount,
    );
  }
}
