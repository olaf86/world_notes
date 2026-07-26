import 'package:cloud_firestore/cloud_firestore.dart';

class UserBlockModel {
  final String blockedUserId;
  final DateTime createdAt;

  const UserBlockModel({required this.blockedUserId, required this.createdAt});

  factory UserBlockModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return UserBlockModel(
      blockedUserId: doc.id,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }
}
