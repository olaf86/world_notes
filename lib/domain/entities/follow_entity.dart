import 'public_profile_entity.dart';

class FollowEdge {
  final String id;
  final String followerUid;
  final String followeeUid;
  final DateTime createdAt;

  const FollowEdge({
    required this.id,
    required this.followerUid,
    required this.followeeUid,
    required this.createdAt,
  });
}

class FollowListItem {
  final PublicProfile profile;
  final DateTime followedAt;

  const FollowListItem({required this.profile, required this.followedAt});
}

class FollowPage {
  final List<FollowListItem> items;
  final Object? nextCursor;
  final bool hasMore;

  const FollowPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });
}
