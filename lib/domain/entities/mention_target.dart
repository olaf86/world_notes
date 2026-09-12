const int maxMessageMentionRecipients = 3;

class MentionTarget {
  final String userId;
  final String displayName;
  final String? photoUrl;

  const MentionTarget({
    required this.userId,
    required this.displayName,
    this.photoUrl,
  });

  @override
  bool operator ==(Object other) =>
      other is MentionTarget && other.userId == userId;

  @override
  int get hashCode => userId.hashCode;
}
