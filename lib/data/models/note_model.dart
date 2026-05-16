import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/note_entity.dart';

class NoteModel {
  final String id;
  final String placeId;
  final DateTime createdAt;
  final int messageCount;

  NoteModel({
    required this.id,
    required this.placeId,
    required this.createdAt,
    this.messageCount = 0,
  });

  factory NoteModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NoteModel(
      id: doc.id,
      placeId: data['placeId'] as String,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      messageCount: (data['messageCount'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'placeId': placeId,
      'createdAt': FieldValue.serverTimestamp(),
      'messageCount': messageCount,
    };
  }

  NoteEntity toEntity() => NoteEntity(
        id: id,
        placeId: placeId,
        createdAt: createdAt,
        messageCount: messageCount,
      );
}
