import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../../config/app_config.dart';
import '../../core/utils/image_upload_util.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/entities/message_thread_item.dart';
import '../../domain/entities/content_report.dart';
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
  Stream<List<MessageThreadItem>> watchMessages({
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
    // A single collection-group query provides the current user's like state
    // for this thread. Its list rule permits only edges owned by that user.
    final ownLikesStream = _firestore
        .collectionGroup('messageLikes')
        .where('placeId', isEqualTo: placeId)
        .where('userId', isEqualTo: currentUserId)
        .where('liked', isEqualTo: true)
        .snapshots();
    late final StreamController<List<MessageThreadItem>> controller;
    QuerySnapshot? publishedSnap;
    QuerySnapshot? ownScheduledSnap;
    QuerySnapshot? ownLikesSnap;
    StreamSubscription<QuerySnapshot>? publishedSubscription;
    StreamSubscription<QuerySnapshot>? ownScheduledSubscription;
    StreamSubscription<QuerySnapshot>? ownLikesSubscription;

    void emitIfReady() {
      final published = publishedSnap;
      final ownScheduled = ownScheduledSnap;
      final ownLikes = ownLikesSnap;
      if (published == null || ownScheduled == null || ownLikes == null) {
        return;
      }

      controller.add(
        _threadItemsFromSnapshots(
          published: published,
          ownScheduled: ownScheduled,
          ownLikes: ownLikes,
          currentUserId: currentUserId,
        ),
      );
    }

    controller = StreamController<List<MessageThreadItem>>(
      onListen: () {
        publishedSubscription = publishedStream.listen((snap) {
          publishedSnap = snap;
          emitIfReady();
        }, onError: controller.addError);
        ownScheduledSubscription = ownScheduledStream.listen((snap) {
          ownScheduledSnap = snap;
          emitIfReady();
        }, onError: controller.addError);
        ownLikesSubscription = ownLikesStream.listen((snap) {
          ownLikesSnap = snap;
          emitIfReady();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await Future.wait([
          if (publishedSubscription != null) publishedSubscription!.cancel(),
          if (ownScheduledSubscription != null)
            ownScheduledSubscription!.cancel(),
          if (ownLikesSubscription != null) ownLikesSubscription!.cancel(),
        ]);
      },
    );

    return controller.stream;
  }

  List<MessageThreadItem> _threadItemsFromSnapshots({
    required QuerySnapshot published,
    required QuerySnapshot ownScheduled,
    required QuerySnapshot ownLikes,
    required String currentUserId,
  }) {
    final likedMessageIds = _likedMessageIds(ownLikes);
    final byId = <String, MessageThreadItem>{};
    for (final doc in [...published.docs, ...ownScheduled.docs]) {
      final item = _threadItemFromDoc(
        doc,
        likedByCurrentUser: likedMessageIds.contains(doc.id),
      );
      final message = item.message;
      if (!message.isVisible) continue;
      if (message.isDeleted && message.author.id != currentUserId) continue;
      byId[message.id] = item;
    }
    return byId.values.toList()..sort(_compareThreadItems);
  }

  MessageThreadItem _threadItemFromDoc(
    QueryDocumentSnapshot doc, {
    required bool likedByCurrentUser,
  }) {
    final model = MessageModel.fromFirestore(doc);
    return MessageThreadItem(
      message: model.toEntity(),
      likeState: MessageLikeState(
        count: model.likeCount,
        likedByCurrentUser: likedByCurrentUser,
      ),
    );
  }

  Set<String> _likedMessageIds(QuerySnapshot snap) {
    return snap.docs
        .map((doc) => doc.get('messageId') as String?)
        .whereType<String>()
        .toSet();
  }

  int _compareThreadItems(MessageThreadItem a, MessageThreadItem b) {
    final publishOrder = b.message.publishAt.compareTo(a.message.publishAt);
    if (publishOrder != 0) return publishOrder;
    return b.message.createdAt.compareTo(a.message.createdAt);
  }

  @override
  Future<List<MessageThreadItem>> getOlderMessages({
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
        .map((doc) => _threadItemFromDoc(doc, likedByCurrentUser: false))
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
    late final HttpsCallableResult<Map<String, dynamic>> result;
    try {
      result = await _functions
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
    } catch (_) {
      await Future.wait([
        for (final path in imageStoragePaths)
          _storage.ref(path).delete().catchError((_) {}),
      ]);
      rethrow;
    }
    final confirmedMessageId = result.data['messageId'] as String? ?? messageId;
    final confirmedPublishAtMillis = result.data['publishAtMillis'] as int?;
    final confirmedPublishAt = confirmedPublishAtMillis == null
        ? publishAt ?? now
        : DateTime.fromMillisecondsSinceEpoch(confirmedPublishAtMillis);
    final model = MessageModel(
      id: confirmedMessageId,
      placeId: placeId,
      userId: userId,
      userName: userName,
      userPhotoUrl: userPhotoUrl,
      content: content,
      imageStoragePaths: imageStoragePaths,
      createdAt: now,
      publishAt: confirmedPublishAt,
      isScheduled: result.data['isScheduled'] as bool,
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
    required ReportReasonCode reasonCode,
  }) async {
    await _functions.httpsCallable('reportMessage').call<Map<String, dynamic>>({
      'messageId': messageId,
      'placeId': placeId,
      'reasonCode': reasonCode.toJson(),
    });
  }

  @override
  Future<void> setMessageLike({
    required String placeId,
    required String messageId,
    required bool liked,
  }) async {
    await _functions.httpsCallable('setMessageLike').call<Map<String, dynamic>>(
      {'placeId': placeId, 'messageId': messageId, 'liked': liked},
    );
  }
}
