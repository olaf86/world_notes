import '../entities/notice_entity.dart';

abstract class NoticeRepository {
  Stream<List<NoticeEntity>> watchNotices(String userId);
  Future<void> markRead({required String userId, required String noticeId});
}
