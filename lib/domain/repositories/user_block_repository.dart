import '../entities/user_block_entity.dart';

abstract class UserBlockRepository {
  Stream<Set<String>> watchBlockedUserIds(String blockerUserId);

  Stream<bool> watchIsBlocked({
    required String blockerUserId,
    required String blockedUserId,
  });

  Stream<List<UserBlock>> watchBlockedUsers(String blockerUserId);

  Future<void> setBlocked({
    required String targetUserId,
    required bool blocked,
  });
}
