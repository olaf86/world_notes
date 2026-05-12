import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/entities/user_entity.dart';

class MessageModel {
  final String id;
  final String noteId;
  final String userId;
  final String userName;
  final String? userPhotoUrl;
  final String content;
  final DateTime createdAt;

  MessageModel({
    required this.id,
    required this.noteId,
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
    required this.content,
    required this.createdAt,
  });

  factory MessageModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MessageModel(
      id: doc.id,
      noteId: data['noteId'] as String,
      userId: data['userId'] as String,
      userName: data['userName'] as String? ?? 'Unknown',
      userPhotoUrl: data['userPhotoUrl'] as String?,
      content: data['content'] as String,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'noteId': noteId,
      'userId': userId,
      'userName': userName,
      'userPhotoUrl': userPhotoUrl,
      'content': content,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  MessageEntity toEntity() => MessageEntity(
        id: id,
        noteId: noteId,
        author: UserEntity(
          id: userId,
          name: userName,
          photoUrl: userPhotoUrl,
        ),
        content: content,
        createdAt: createdAt,
      );
}
