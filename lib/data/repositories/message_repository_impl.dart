import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../config/app_config.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/message_repository.dart';
import '../models/message_model.dart';

class MessageRepositoryImpl implements MessageRepository {
  final FirebaseFirestore _firestore;
  final _uuid = const Uuid();

  MessageRepositoryImpl({required FirebaseFirestore firestore})
      : _firestore = firestore;

  CollectionReference get _messages => _firestore.collection('messages');

  @override
  Stream<List<MessageEntity>> watchMessages(String noteId) {
    return _messages
        .where('noteId', isEqualTo: noteId)
        .orderBy('createdAt', descending: true)
        .limit(AppConfig.messagesPageSize)
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => MessageModel.fromFirestore(doc).toEntity()).toList());
  }

  @override
  Future<List<MessageEntity>> getOlderMessages({
    required String noteId,
    required String beforeMessageId,
    required int limit,
  }) async {
    final pivotDoc = await _messages.doc(beforeMessageId).get();
    if (!pivotDoc.exists) return [];

    final snap = await _messages
        .where('noteId', isEqualTo: noteId)
        .orderBy('createdAt', descending: true)
        .startAfterDocument(pivotDoc)
        .limit(limit)
        .get();

    return snap.docs
        .map((doc) => MessageModel.fromFirestore(doc).toEntity())
        .toList();
  }

  @override
  Future<MessageEntity> sendMessage({
    required String noteId,
    required String content,
    required String userId,
  }) async {
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final userName = userDoc.exists
        ? (userDoc.data()!['name'] as String? ?? 'User')
        : 'User';
    final userPhoto = userDoc.exists
        ? (userDoc.data()!['photoUrl'] as String?)
        : null;

    final id = _uuid.v4();
    final model = MessageModel(
      id: id,
      noteId: noteId,
      userId: userId,
      userName: userName,
      userPhotoUrl: userPhoto,
      content: content,
      createdAt: DateTime.now(),
    );

    await _messages.doc(id).set(model.toFirestore());

    // Increment message count on the note
    await _firestore
        .collection('notes')
        .where('placeId', isEqualTo: noteId)
        .limit(1)
        .get()
        .then((snap) {
      if (snap.docs.isNotEmpty) {
        snap.docs.first.reference.update({
          'messageCount': FieldValue.increment(1),
        });
      }
    });

    return model.toEntity();
  }
}
