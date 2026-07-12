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
  final List<String> imageStoragePaths;
  final DateTime createdAt;
  final DateTime publishAt;
  final int likeCount;
  final bool isDeleted;
  final DateTime? deletedAt;
  final String? deletedReason;
  final bool isVisible;
  final bool isPubliclyVisible;
  final bool isSensitive;
  final bool reviewRequired;

  MessageModel({
    required this.id,
    required this.placeId,
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
    required this.content,
    this.imageStoragePaths = const [],
    required this.createdAt,
    required this.publishAt,
    this.likeCount = 0,
    this.isDeleted = false,
    this.deletedAt,
    this.deletedReason,
    this.isVisible = true,
    this.isPubliclyVisible = false,
    this.isSensitive = false,
    this.reviewRequired = false,
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
      imageStoragePaths: List<String>.from(
        (data['imageStoragePaths'] as List<dynamic>? ?? const [])
            .whereType<String>(),
      ),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      publishAt: (data['publishAt'] as Timestamp).toDate(),
      likeCount: (data['likeCount'] as num?)?.toInt() ?? 0,
      isDeleted: data['isDeleted'] as bool,
      deletedAt: (data['deletedAt'] as Timestamp?)?.toDate(),
      deletedReason: data['deletedReason'] as String?,
      isVisible: data['isVisible'] as bool,
      isPubliclyVisible: data['isPubliclyVisible'] as bool,
      isSensitive: data['isSensitive'] as bool,
      reviewRequired: data['reviewRequired'] as bool,
    );
  }

  MessageEntity toEntity() => MessageEntity(
    id: id,
    placeId: placeId,
    author: UserEntity(id: userId, name: userName, photoUrl: userPhotoUrl),
    content: content,
    imageStoragePaths: imageStoragePaths,
    createdAt: createdAt,
    publishAt: publishAt,
    isDeleted: isDeleted,
    deletedAt: deletedAt,
    deletedReason: deletedReason,
    isVisible: isVisible,
    isSensitive: isSensitive,
    reviewRequired: reviewRequired,
  );
}
