import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/note_visitor_entity.dart';

class NoteVisitorModel {
  final String userId;
  final String? displayName;
  final String? photoUrl;
  final DateTime firstVisitedAt;
  final DateTime lastVisitedAt;
  final int visitCount;
  final bool isMaintainer;

  const NoteVisitorModel({
    required this.userId,
    this.displayName,
    this.photoUrl,
    required this.firstVisitedAt,
    required this.lastVisitedAt,
    required this.visitCount,
    this.isMaintainer = false,
  });

  factory NoteVisitorModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    final lastVisitedAt =
        (data['lastVisitedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    return NoteVisitorModel(
      userId: data['userId'] as String? ?? doc.id,
      displayName: data['displayName'] as String?,
      photoUrl: data['photoUrl'] as String?,
      firstVisitedAt:
          (data['firstVisitedAt'] as Timestamp?)?.toDate() ?? lastVisitedAt,
      lastVisitedAt: lastVisitedAt,
      visitCount: data['visitCount'] as int? ?? 0,
      isMaintainer: data['isMaintainer'] as bool? ?? false,
    );
  }

  NoteVisitor toEntity() => NoteVisitor(
    userId: userId,
    displayName: displayName,
    photoUrl: photoUrl,
    firstVisitedAt: firstVisitedAt,
    lastVisitedAt: lastVisitedAt,
    visitCount: visitCount,
    isMaintainer: isMaintainer,
  );
}
