import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/notice_entity.dart';

class NoticeModel {
  final String id;
  final String category;
  final String severity;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? sourceType;
  final String? sourceId;
  final NoticeActionEntity? action;

  const NoticeModel({
    required this.id,
    required this.category,
    required this.severity,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.sourceType,
    this.sourceId,
    this.action,
  });

  factory NoticeModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final createdAt = data['createdAt'];
    return NoticeModel(
      id: doc.id,
      category: data['category'] as String? ?? 'system',
      severity: data['severity'] as String? ?? 'info',
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      readAt: (data['readAt'] as Timestamp?)?.toDate(),
      sourceType: data['sourceType'] as String?,
      sourceId: data['sourceId'] as String?,
      action: _actionFromJson(data['action']),
    );
  }

  NoticeEntity toEntity() => NoticeEntity(
    id: id,
    category: category,
    severity: severity,
    title: title,
    body: body,
    createdAt: createdAt,
    readAt: readAt,
    sourceType: sourceType,
    sourceId: sourceId,
    action: action,
  );
}

NoticeActionEntity? _actionFromJson(Object? value) {
  if (value is! Map) return null;
  final type = value['type'];
  final route = value['route'];
  final params = value['params'];
  if (type != 'route' || route is! String || route.isEmpty) return null;
  return NoticeActionEntity(
    route: route,
    params: params is Map
        ? params.map((key, value) => MapEntry(key.toString(), value))
        : const {},
  );
}
