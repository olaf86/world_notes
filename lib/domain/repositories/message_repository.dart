import '../entities/message_entity.dart';

abstract class MessageRepository {
  Stream<List<MessageEntity>> watchMessages({
    required String placeId,
    required String currentUserId,
  });
  Future<List<MessageEntity>> getOlderMessages({
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
    List<int>? imageBytes,
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
    required String reporterId,
    required String reason,
  });
}
