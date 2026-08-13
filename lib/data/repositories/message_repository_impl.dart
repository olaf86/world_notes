import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../../config/app_config.dart';
import '../../core/utils/image_upload_util.dart';
import '../../services/world_firebase_clients.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/entities/message_thread_item.dart';
import '../../domain/entities/content_report.dart';
import '../../domain/repositories/message_repository.dart';
import '../models/message_model.dart';

const _readableMessageModerationActions = <String>[
  'pending',
  'allow',
  'sensitive',
  'review',
];

class MessageRepositoryImpl implements MessageRepository {
  final FirebaseFirestore _firestore;
  final WorldFunctionsClient _functions;
  final FirebaseStorage _storage;
  final _uuid = const Uuid();

  MessageRepositoryImpl({
    required FirebaseFirestore firestore,
    required WorldFunctionsClient functions,
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
    Set<String> blockedUserIds = const {},
  }) {
    final publishedStream = _messagesOf(placeId)
        .where('isPubliclyVisible', isEqualTo: true)
        .where('isVisible', isEqualTo: true)
        .where('moderationAction', whereIn: _readableMessageModerationActions)
        .orderBy('publishAt', descending: true)
        .limit(AppConfig.messagesPageSize)
        .snapshots();
    final ownScheduledStream = _messagesOf(placeId)
        .where('userId', isEqualTo: currentUserId)
        .where('isPubliclyVisible', isEqualTo: false)
        .where('moderationAction', whereIn: _readableMessageModerationActions)
        .orderBy('publishAt')
        .limit(AppConfig.messagesPageSize)
        .snapshots();
    late final StreamController<List<MessageThreadItem>> controller;
    QuerySnapshot? publishedSnap;
    QuerySnapshot? ownScheduledSnap;
    StreamSubscription<QuerySnapshot>? publishedSubscription;
    StreamSubscription<QuerySnapshot>? ownScheduledSubscription;
    final ownLikeSnapshots = <String, DocumentSnapshot>{};
    final ownLikeSubscriptions =
        <String, StreamSubscription<DocumentSnapshot>>{};

    Set<String> currentMessageIds() {
      return {
        ...?publishedSnap?.docs.map((doc) => doc.id),
        ...?ownScheduledSnap?.docs.map((doc) => doc.id),
      };
    }

    void emitIfReady() {
      final published = publishedSnap;
      final ownScheduled = ownScheduledSnap;
      if (published == null || ownScheduled == null) {
        return;
      }
      final messageIds = currentMessageIds();
      if (!messageIds.every(ownLikeSnapshots.containsKey)) return;
      final likedMessageIds = messageIds.where((messageId) {
        final snapshot = ownLikeSnapshots[messageId];
        final data = snapshot?.data();
        return snapshot?.exists == true &&
            data is Map<String, dynamic> &&
            data['liked'] == true;
      }).toSet();

      controller.add(
        _threadItemsFromSnapshots(
          published: published,
          ownScheduled: ownScheduled,
          likedMessageIds: likedMessageIds,
          currentUserId: currentUserId,
          blockedUserIds: blockedUserIds,
        ),
      );
    }

    void synchronizeOwnLikeSubscriptions() {
      if (publishedSnap == null || ownScheduledSnap == null) return;
      final messageIds = currentMessageIds();
      final staleMessageIds = ownLikeSubscriptions.keys
          .where((messageId) => !messageIds.contains(messageId))
          .toList();
      for (final messageId in staleMessageIds) {
        final subscription = ownLikeSubscriptions.remove(messageId);
        ownLikeSnapshots.remove(messageId);
        if (subscription != null) unawaited(subscription.cancel());
      }
      for (final messageId in messageIds) {
        if (ownLikeSubscriptions.containsKey(messageId)) continue;
        late final StreamSubscription<DocumentSnapshot> subscription;
        subscription = _messagesOf(placeId)
            .doc(messageId)
            .collection('messageLikes')
            .doc(currentUserId)
            .snapshots()
            .listen(
              (snapshot) {
                if (ownLikeSubscriptions[messageId] != subscription) return;
                ownLikeSnapshots[messageId] = snapshot;
                emitIfReady();
              },
              onError: (Object error, StackTrace stackTrace) {
                if (ownLikeSubscriptions[messageId] == subscription) {
                  controller.addError(error, stackTrace);
                }
              },
            );
        ownLikeSubscriptions[messageId] = subscription;
      }
    }

    controller = StreamController<List<MessageThreadItem>>(
      onListen: () {
        publishedSubscription = publishedStream.listen((snap) {
          publishedSnap = snap;
          synchronizeOwnLikeSubscriptions();
          emitIfReady();
        }, onError: controller.addError);
        ownScheduledSubscription = ownScheduledStream.listen((snap) {
          ownScheduledSnap = snap;
          synchronizeOwnLikeSubscriptions();
          emitIfReady();
        }, onError: controller.addError);
      },
      onCancel: () async {
        final likeSubscriptions = ownLikeSubscriptions.values.toList();
        ownLikeSubscriptions.clear();
        ownLikeSnapshots.clear();
        await Future.wait([
          if (publishedSubscription != null) publishedSubscription!.cancel(),
          if (ownScheduledSubscription != null)
            ownScheduledSubscription!.cancel(),
          ...likeSubscriptions.map((subscription) => subscription.cancel()),
        ]);
      },
    );

    return controller.stream;
  }

  List<MessageThreadItem> _threadItemsFromSnapshots({
    required QuerySnapshot published,
    required QuerySnapshot ownScheduled,
    required Set<String> likedMessageIds,
    required String currentUserId,
    required Set<String> blockedUserIds,
  }) {
    final byId = <String, MessageThreadItem>{};
    for (final doc in [...published.docs, ...ownScheduled.docs]) {
      final item = _threadItemFromDoc(
        doc,
        likedByCurrentUser: likedMessageIds.contains(doc.id),
      );
      final message = item.message;
      if (blockedUserIds.contains(message.author.id)) continue;
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
    Set<String> blockedUserIds = const {},
  }) async {
    final pivotDoc = await _messagesOf(placeId).doc(beforeMessageId).get();
    if (!pivotDoc.exists) return [];

    final snap = await _messagesOf(placeId)
        .where('isPubliclyVisible', isEqualTo: true)
        .where('isVisible', isEqualTo: true)
        .where('moderationAction', whereIn: _readableMessageModerationActions)
        .orderBy('publishAt', descending: true)
        .startAfterDocument(pivotDoc)
        .limit(limit)
        .get();

    return snap.docs
        .map((doc) => _threadItemFromDoc(doc, likedByCurrentUser: false))
        .where((item) => !blockedUserIds.contains(item.message.author.id))
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
      // before the original response was lost. Direct Storage reads are
      // intentionally unavailable; the callable verifies the exact object.
      if (error.code != 'unauthorized') rethrow;
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
      // Immutable uploads are server-cleaned when they remain unreferenced.
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
