import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/entities/user_entity.dart';

class MessageModel {
  final String id;
  final String placeId;
  final String userId;
  final String userName;
  final String? userPhotoUrl;
  final String content;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime publishAt;
  final bool isDeleted;
  final DateTime? deletedAt;
  final bool isVisible;
  final bool isPubliclyVisible;

  MessageModel({
    required this.id,
    required this.placeId,
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
    required this.content,
    this.imageUrl,
    required this.createdAt,
    required this.publishAt,
    this.isDeleted = false,
    this.deletedAt,
    this.isVisible = true,
    this.isPubliclyVisible = false,
  });

  factory MessageModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MessageModel(
      id: doc.id,
      placeId: data['placeId'] as String,
      userId: data['userId'] as String,
      userName: data['userName'] as String? ?? 'Unknown',
      userPhotoUrl: data['userPhotoUrl'] as String?,
      content: data['content'] as String,
      imageUrl: data['imageUrl'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      publishAt: (data['publishAt'] as Timestamp).toDate(),
      isDeleted: data['isDeleted'] as bool? ?? false,
      deletedAt: (data['deletedAt'] as Timestamp?)?.toDate(),
      isVisible: data['isVisible'] as bool? ?? true,
      isPubliclyVisible: data['isPubliclyVisible'] as bool? ?? true,
    );
  }

  MessageEntity toEntity() => MessageEntity(
    id: id,
    placeId: placeId,
    author: UserEntity(id: userId, name: userName, photoUrl: userPhotoUrl),
    content: content,
    imageUrl: imageUrl,
    createdAt: createdAt,
    publishAt: publishAt,
    isDeleted: isDeleted,
    deletedAt: deletedAt,
    isVisible: isVisible,
  );
}
