import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/notice_entity.dart';
import '../../domain/repositories/notice_repository.dart';
import '../models/notice_model.dart';

const _firestoreBatchWriteLimit = 500;

class NoticeRepositoryImpl implements NoticeRepository {
  final FirebaseFirestore _firestore;

  NoticeRepositoryImpl({required FirebaseFirestore firestore})
    : _firestore = firestore;

  CollectionReference _noticesOf(String userId) =>
      _firestore.collection('users').doc(userId).collection('notices');

  @override
  Stream<List<NoticeEntity>> watchNotices(String userId) {
    return _noticesOf(userId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => NoticeModel.fromFirestore(doc).toEntity())
              .toList(),
        );
  }

  @override
  Future<void> markRead({
    required String userId,
    required String noticeId,
  }) async {
    await _noticesOf(
      userId,
    ).doc(noticeId).update({'readAt': FieldValue.serverTimestamp()});
  }

  @override
  Future<void> markAllRead({required String userId}) async {
    final unread = await _noticesOf(userId).where('readAt', isNull: true).get();
    for (
      var offset = 0;
      offset < unread.docs.length;
      offset += _firestoreBatchWriteLimit
    ) {
      final end = (offset + _firestoreBatchWriteLimit).clamp(
        0,
        unread.docs.length,
      );
      final batch = _firestore.batch();
      for (final notice in unread.docs.sublist(offset, end)) {
        batch.update(notice.reference, {
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }
}
