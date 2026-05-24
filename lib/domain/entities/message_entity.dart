import 'user_entity.dart';

class MessageEntity {
  final String id;
  final String placeId;
  final UserEntity author;
  final String content;
  final String? imageUrl;
  final DateTime createdAt;

  /// True for optimistic messages that haven't been confirmed by Firestore yet.
  /// Confirmed messages coming from the snapshot stream always have this false.
  final bool isPending;

  const MessageEntity({
    required this.id,
    required this.placeId,
    required this.author,
    required this.content,
    this.imageUrl,
    required this.createdAt,
    this.isPending = false,
  });
}
