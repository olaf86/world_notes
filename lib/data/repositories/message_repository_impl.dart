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
  }) {
    final publishedStream = _messagesOf(placeId)
        .where('isPubliclyVisible', isEqualTo: true)
        .where('isVisible', isEqualTo: true)
        .orderBy('publishAt', descending: true)
        .limit(AppConfig.messagesPageSize)
        .snapshots();
    final ownScheduledStream = _messagesOf(placeId)
        .where('userId', isEqualTo: currentUserId)
        .where('isPubliclyVisible', isEqualTo: false)
        .orderBy('publishAt')
        .limit(AppConfig.messagesPageSize)
        .snapshots();

    late final StreamController<List<MessageEntity>> controller;
    QuerySnapshot? publishedSnap;
    QuerySnapshot? ownScheduledSnap;
    StreamSubscription<QuerySnapshot>? publishedSub;
    StreamSubscription<QuerySnapshot>? ownScheduledSub;

    void emitIfReady() {
      final published = publishedSnap;
      final ownScheduled = ownScheduledSnap;
      if (published == null || ownScheduled == null) return;

      final byId = <String, MessageEntity>{};
      for (final doc in [...published.docs, ...ownScheduled.docs]) {
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
        ownScheduledSub = ownScheduledStream.listen((snap) {
          ownScheduledSnap = snap;
          emitIfReady();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await Future.wait([
          if (publishedSub != null) publishedSub!.cancel(),
          if (ownScheduledSub != null) ownScheduledSub!.cancel(),
        ]);
      },
    );

    return controller.stream;
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
        .where('isPubliclyVisible', isEqualTo: true)
        .where('isVisible', isEqualTo: true)
        .orderBy('publishAt', descending: true)
        .startAfterDocument(pivotDoc)
        .limit(limit)
        .get();

    return snap.docs
        .map((doc) => MessageModel.fromFirestore(doc).toEntity())
        .toList();
  }

  Future<String> _uploadImage({
    required List<int> bytes,
    required String placeId,
    required String userId,
    required String messageId,
    required int imageIndex,
  }) async {
    final path = ImageUploadUtil.messageStoragePath(
      placeId: placeId,
      userId: userId,
      messageId: messageId,
      imageIndex: imageIndex,
    );
    final ref = _storage.ref(path);
    try {
      await ref.putData(
        Uint8List.fromList(bytes),
        SettableMetadata(contentType: 'image/webp'),
      );
    } on FirebaseException catch (error) {
      // A callable retry may reuse an image that was uploaded successfully
      // before the original response was lost.
      if (error.code != 'unauthorized') rethrow;
      final metadata = await ref.getMetadata();
      if (metadata.contentType != 'image/webp') rethrow;
    }
    return path;
  }

  @override
  Future<MessageEntity> sendMessage({
    String? id,
    required String placeId,
    required String content,
    required String userId,
    required String userName,
    String? userPhotoUrl,
    List<List<int>> imageBytesList = const [],
    DateTime? publishAt,
  }) async {
    final messageId = id ?? _uuid.v7();
    final imageStoragePaths = await Future.wait([
      for (var i = 0; i < imageBytesList.length; i += 1)
        _uploadImage(
          bytes: imageBytesList[i],
          placeId: placeId,
          userId: userId,
          messageId: messageId,
          imageIndex: i,
        ),
    ]);

    final now = DateTime.now();
    final result = await _functions
        .httpsCallable('sendMessage')
        .call<Map<String, dynamic>>({
          'messageId': messageId,
          'placeId': placeId,
          'content': content,
          if (imageStoragePaths.isNotEmpty)
            'imageStoragePaths': imageStoragePaths,
          if (publishAt != null)
            'publishAtMillis': publishAt.millisecondsSinceEpoch,
        });
    final confirmedMessageId = result.data['messageId'] as String? ?? messageId;
    final model = MessageModel(
      id: confirmedMessageId,
      placeId: placeId,
      userId: userId,
      userName: userName,
      userPhotoUrl: userPhotoUrl,
      content: content,
      imageStoragePaths: imageStoragePaths,
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
    await _functions.httpsCallable('deleteMessage').call<Map<String, dynamic>>({
      'placeId': placeId,
      'messageId': messageId,
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
    required String reason,
  }) async {
    await _functions.httpsCallable('reportMessage').call<Map<String, dynamic>>({
      'messageId': messageId,
      'placeId': placeId,
      'reason': reason,
    });
  }
}
