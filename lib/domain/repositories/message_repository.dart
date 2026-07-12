import '../entities/message_entity.dart';
import '../entities/message_thread_item.dart';

abstract class MessageRepository {
  Stream<List<MessageThreadItem>> watchMessages({
    required String placeId,
    required String currentUserId,
  });
  Future<List<MessageThreadItem>> getOlderMessages({
    required String placeId,
    required String beforeMessageId,
    required int limit,
  });
  Future<MessageEntity> sendMessage({
    String? id,
    required String placeId,
    required String content,
    required String userId,
    required String userName,
    String? userPhotoUrl,
    List<List<int>> imageBytesList = const [],
    DateTime? publishAt,
  });

  /// Soft-deletes a message. Only the author may call this.
  Future<void> deleteMessage({
    required String placeId,
    required String messageId,
  });

  /// Cancels an unpublished scheduled message and frees its reserved slot.
  Future<void> cancelScheduledMessage({
    required String placeId,
    required String messageId,
  });

  /// Submits a user report for a message.
  Future<void> reportMessage({
    required String messageId,
    required String placeId,
    required String reason,
  });

  /// Sets the current user's final desired like state for a message.
  Future<void> setMessageLike({
    required String placeId,
    required String messageId,
    required bool liked,
  });
}
