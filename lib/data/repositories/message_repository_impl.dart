import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../../config/app_config.dart';
import '../../core/utils/image_upload_util.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/message_repository.dart';
import '../models/message_model.dart';

class MessageRepositoryImpl implements MessageRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;
  final _uuid = const Uuid();

  MessageRepositoryImpl({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required FirebaseStorage storage,
  }) : _firestore = firestore,
       _functions = functions,
       _storage = storage;

  // Messages live in a subcollection under their place:
  //   places/{placeId}/messages/{messageId}
  // This lets security rules gate reads on the parent note's visibility +
  // membership without a per-message field lookup, and keeps a private note's
  // messages physically scoped to that note.
  CollectionReference _messagesOf(String placeId) =>
      _firestore.collection('places').doc(placeId).collection('messages');

  @override
  Stream<List<MessageEntity>> watchMessages({
    required String placeId,
    required String currentUserId,
    required DateTime now,
  }) {
    final publishCutoff = now.subtract(const Duration(seconds: 5));
    final publishedStream = _messagesOf(placeId)
        .where('isPubliclyVisible', isEqualTo: true)
        .where('isVisible', isEqualTo: true)
        .where(
          'publishAt',
          isLessThanOrEqualTo: Timestamp.fromDate(publishCutoff),
        )
        .orderBy('publishAt', descending: true)
        .limit(AppConfig.messagesPageSize)
        .snapshots();
    // Keep a separate own-message stream without a publishAt cutoff. The
    // public stream's cutoff is fixed when the subscription is created, so a
    // message posted after opening the screen can otherwise be excluded until
    // the clock provider rebuilds this query.
    final ownMessagesStream = _messagesOf(placeId)
        .where('userId', isEqualTo: currentUserId)
        .orderBy('publishAt', descending: true)
        .limit(AppConfig.messagesPageSize)
        .snapshots();

    late final StreamController<List<MessageEntity>> controller;
    QuerySnapshot? publishedSnap;
    QuerySnapshot? ownMessagesSnap;
    StreamSubscription<QuerySnapshot>? publishedSub;
    StreamSubscription<QuerySnapshot>? ownMessagesSub;

    void emitIfReady() {
      final published = publishedSnap;
      final ownMessages = ownMessagesSnap;
      if (published == null || ownMessages == null) return;

      final byId = <String, MessageEntity>{};
      for (final doc in [...published.docs, ...ownMessages.docs]) {
        final message = MessageModel.fromFirestore(doc).toEntity();
        if (!message.isVisible) continue;
        if (message.isDeleted && message.author.id != currentUserId) continue;
        byId[message.id] = message;
      }

      final messages = byId.values.toList()
        ..sort((a, b) {
          final publishOrder = b.publishAt.compareTo(a.publishAt);
          if (publishOrder != 0) return publishOrder;
          return b.createdAt.compareTo(a.createdAt);
        });
      controller.add(messages);
    }

    controller = StreamController<List<MessageEntity>>(
      onListen: () {
        publishedSub = publishedStream.listen((snap) {
          publishedSnap = snap;
          emitIfReady();
        }, onError: controller.addError);
        ownMessagesSub = ownMessagesStream.listen((snap) {
          ownMessagesSnap = snap;
          emitIfReady();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await Future.wait([
          if (publishedSub != null) publishedSub!.cancel(),
          if (ownMessagesSub != null) ownMessagesSub!.cancel(),
        ]);
      },
    );

    return controller.stream;
  }

  @override
  Future<List<MessageEntity>> getOlderMessages({
    required String placeId,
    required DateTime now,
    required String beforeMessageId,
    required int limit,
  }) async {
    final pivotDoc = await _messagesOf(placeId).doc(beforeMessageId).get();
    if (!pivotDoc.exists) return [];

    final snap = await _messagesOf(placeId)
        .where('isPubliclyVisible', isEqualTo: true)
        .where('isVisible', isEqualTo: true)
        .where(
          'publishAt',
          isLessThanOrEqualTo: Timestamp.fromDate(
            now.subtract(const Duration(seconds: 5)),
          ),
        )
        .orderBy('publishAt', descending: true)
        .startAfterDocument(pivotDoc)
        .limit(limit)
        .get();

    return snap.docs
        .map((doc) => MessageModel.fromFirestore(doc).toEntity())
        .toList();
  }

  Future<String?> _uploadImage({
    required List<int> bytes,
    required String? name,
    required String userId,
  }) async {
    final ext = ImageUploadUtil.extensionForFileName(name);
    final ref = _storage.ref().child('messages/$userId/${_uuid.v4()}.$ext');
    await ref.putData(
      Uint8List.fromList(bytes),
      SettableMetadata(
        contentType: ImageUploadUtil.contentTypeForExtension(ext),
      ),
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
    DateTime? publishAt,
  }) async {
    String? imageUrl;
    if (imageBytes != null) {
      imageUrl = await _uploadImage(
        bytes: imageBytes,
        name: imageName,
        userId: userId,
      );
    }

    final now = DateTime.now();
    final result = await _functions
        .httpsCallable('sendMessage')
        .call<Map<String, dynamic>>({
          'placeId': placeId,
          'content': content,
          'imageUrl': ?imageUrl,
          if (publishAt != null)
            'publishAtMillis': publishAt.millisecondsSinceEpoch,
        });
    final messageId = result.data['messageId'] as String? ?? id ?? _uuid.v4();
    final model = MessageModel(
      id: messageId,
      placeId: placeId,
      userId: userId,
      userName: userName,
      userPhotoUrl: userPhotoUrl,
      content: content,
      imageUrl: imageUrl,
      createdAt: now,
      publishAt: publishAt ?? now,
    );

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
  Future<void> cancelScheduledMessage({
    required String placeId,
    required String messageId,
  }) async {
    await _functions
        .httpsCallable('cancelScheduledMessage')
        .call<Map<String, dynamic>>({
          'placeId': placeId,
          'messageId': messageId,
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
