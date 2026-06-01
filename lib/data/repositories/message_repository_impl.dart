import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../../config/app_config.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/message_repository.dart';
import '../models/message_model.dart';

class MessageRepositoryImpl implements MessageRepository {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final _uuid = const Uuid();

  MessageRepositoryImpl({
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
  })  : _firestore = firestore,
        _storage = storage;

  // Messages live in a subcollection under their place:
  //   places/{placeId}/messages/{messageId}
  // This lets security rules gate reads on the parent note's visibility +
  // membership without a per-message field lookup, and keeps a private note's
  // messages physically scoped to that note.
  CollectionReference _messagesOf(String placeId) =>
      _firestore.collection('places').doc(placeId).collection('messages');

  @override
  Stream<List<MessageEntity>> watchMessages(String placeId) {
    return _messagesOf(placeId)
        .orderBy('createdAt', descending: true)
        .limit(AppConfig.messagesPageSize)
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => MessageModel.fromFirestore(doc).toEntity()).toList());
  }

  @override
  Future<List<MessageEntity>> getOlderMessages({
    required String placeId,
    required String beforeMessageId,
    required int limit,
  }) async {
    final pivotDoc = await _messagesOf(placeId).doc(beforeMessageId).get();
    if (!pivotDoc.exists) return [];

    final snap = await _messagesOf(placeId)
        .orderBy('createdAt', descending: true)
        .startAfterDocument(pivotDoc)
        .limit(limit)
        .get();

    return snap.docs
        .map((doc) => MessageModel.fromFirestore(doc).toEntity())
        .toList();
  }

  Future<String?> _uploadImage({
    required List<int> bytes,
    required String name,
    required String userId,
  }) async {
    final ext = name.contains('.') ? name.split('.').last : 'jpg';
    final ref = _storage
        .ref()
        .child('messages/$userId/${_uuid.v4()}.$ext');
    await ref.putData(
      Uint8List.fromList(bytes),
      SettableMetadata(contentType: 'image/$ext'),
    );
    return ref.getDownloadURL();
  }

  @override
  Future<MessageEntity> sendMessage({
    String? id,
    required String placeId,
    required String content,
    required String userId,
    required String userName,
    String? userPhotoUrl,
    List<int>? imageBytes,
    String? imageName,
  }) async {
    String? imageUrl;
    if (imageBytes != null && imageName != null) {
      imageUrl = await _uploadImage(
        bytes: imageBytes,
        name: imageName,
        userId: userId,
      );
    }

    final messageId = id ?? _uuid.v4();
    final model = MessageModel(
      id: messageId,
      placeId: placeId,
      userId: userId,
      userName: userName,
      userPhotoUrl: userPhotoUrl,
      content: content,
      imageUrl: imageUrl,
      createdAt: DateTime.now(),
    );

    await _messagesOf(placeId).doc(messageId).set(model.toFirestore());

    // place.messageCount / lastMessageAt are updated by the onMessageCreated
    // Cloud Function trigger, not the client (clients can no longer write
    // those fields). The new message itself streams in immediately; the note's
    // counter/sort updates a moment later when the trigger commits.

    return model.toEntity();
  }

  @override
  Future<void> deleteMessage({
    required String placeId,
    required String messageId,
  }) async {
    await _messagesOf(placeId).doc(messageId).update({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> reportMessage({
    required String messageId,
    required String placeId,
    required String reporterId,
    required String reason,
  }) async {
    final batch = _firestore.batch();

    final reportRef = _firestore.collection('reports').doc();
    batch.set(reportRef, {
      'messageId': messageId,
      'placeId': placeId,
      'reporterId': reporterId,
      'reason': reason,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    batch.update(_messagesOf(placeId).doc(messageId), {
      'reportCount': FieldValue.increment(1),
    });

    await batch.commit();
  }
}
