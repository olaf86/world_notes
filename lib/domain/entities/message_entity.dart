import 'user_entity.dart';

class MessageEntity {
  final String id;
  final String noteId;
  final UserEntity author;
  final String content;
  final String? imageUrl;
  final DateTime createdAt;

  const MessageEntity({
    required this.id,
    required this.noteId,
    required this.author,
    required this.content,
    this.imageUrl,
    required this.createdAt,
  });
}
