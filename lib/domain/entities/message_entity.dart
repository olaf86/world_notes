import 'user_entity.dart';

class MessageEntity {
  final String id;
  final String placeId;
  final UserEntity author;
  final String content;
  final String? imageStoragePath;
  final DateTime createdAt;
  final DateTime publishAt;

  /// True for optimistic messages that haven't been confirmed by Firestore yet.
  final bool isPending;

  /// True when the author has soft-deleted this message.
  final bool isDeleted;
  final DateTime? deletedAt;

  /// False when Cloud Functions auto-moderation has hidden this message.
  /// Invisible messages are filtered out server-side and never reach the client.
  final bool isVisible;

  const MessageEntity({
    required this.id,
    required this.placeId,
    required this.author,
    required this.content,
    this.imageStoragePath,
    required this.createdAt,
    required this.publishAt,
    this.isPending = false,
    this.isDeleted = false,
    this.deletedAt,
    this.isVisible = true,
  });

  bool isPublishedAt(DateTime now) => !now.isBefore(publishAt);
  bool get isPublished => isPublishedAt(DateTime.now());
}
