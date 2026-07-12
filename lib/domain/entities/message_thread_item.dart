import 'message_entity.dart';

class MessageLikeState {
  final int count;
  final bool likedByCurrentUser;

  const MessageLikeState({this.count = 0, this.likedByCurrentUser = false});
}

class MessageThreadItem {
  final MessageEntity message;
  final MessageLikeState likeState;

  const MessageThreadItem({
    required this.message,
    this.likeState = const MessageLikeState(),
  });
}
