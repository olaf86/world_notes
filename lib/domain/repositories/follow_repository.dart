import '../entities/follow_entity.dart';
import '../entities/public_profile_entity.dart';

abstract class FollowRepository {
  Stream<PublicProfile?> watchPublicProfile(String userId);

  Stream<bool> watchIsFollowing({
    required String followerUid,
    required String followeeUid,
  });

  Future<void> setFollowing({
    required String targetUserId,
    required bool following,
  });

  Future<FollowPage> listFollowing({
    required String userId,
    Object? cursor,
    int limit = 20,
    Set<String> excludedUserIds = const {},
  });

  Future<FollowPage> listFollowers({
    required String userId,
    Object? cursor,
    int limit = 20,
    Set<String> excludedUserIds = const {},
  });
}
