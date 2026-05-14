import '../entities/message_entity.dart';

abstract class MessageRepository {
  Stream<List<MessageEntity>> watchMessages(String noteId);
  Future<List<MessageEntity>> getOlderMessages({
    required String noteId,
    required String beforeMessageId,
    required int limit,
  });
  Future<MessageEntity> sendMessage({
    required String noteId,
    required String content,
    required String userId,
    List<int>? imageBytes,
    String? imageName,
  });
}
