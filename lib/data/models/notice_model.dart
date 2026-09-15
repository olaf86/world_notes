import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/notice_entity.dart';

class NoticeModel {
  final String id;
  final int schemaVersion;
  final String templateId;
  final int templateVersion;
  final String locale;
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
    required this.schemaVersion,
    required this.templateId,
    required this.templateVersion,
    required this.locale,
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
    final readAt = data['readAt'];
    final content = data['content'];
    if (data['schemaVersion'] != currentNoticeSchemaVersion ||
        data['templateId'] is! String ||
        data['templateVersion'] is! int ||
        content is! Map ||
        content['locale'] is! String ||
        content['title'] is! String ||
        content['body'] is! String ||
        createdAt is! Timestamp ||
        (readAt != null && readAt is! Timestamp)) {
      throw const FormatException('Notice fields are invalid.');
    }
    return NoticeModel(
      id: doc.id,
      schemaVersion: data['schemaVersion'] as int,
      templateId: data['templateId'] as String,
      templateVersion: data['templateVersion'] as int,
      locale: content['locale'] as String,
      category: data['category'] as String? ?? 'system',
      severity: data['severity'] as String? ?? 'info',
      title: content['title'] as String,
      body: content['body'] as String,
      createdAt: createdAt.toDate(),
      readAt: (readAt as Timestamp?)?.toDate(),
      sourceType: data['sourceType'] as String?,
      sourceId: data['sourceId'] as String?,
      action: _actionFromJson(data['action']),
    );
  }

  NoticeEntity toEntity() => NoticeEntity(
    id: id,
    schemaVersion: schemaVersion,
    templateId: templateId,
    templateVersion: templateVersion,
    locale: locale,
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
  final normalizedParams = params is Map
      ? params.map((key, value) => MapEntry(key.toString(), value))
      : const <String, Object?>{};
  if (!_isValidAction(route, normalizedParams)) return null;
  return NoticeActionEntity(route: route, params: normalizedParams);
}

bool _isValidAction(String route, Map<String, Object?> params) {
  switch (route) {
    case 'userProfile':
      return _hasOnly(params, const {'userId'}) &&
          _isNonEmptyString(params['userId']);
    case 'mapNote':
      return _hasOnly(params, const {
            'worldId',
            'placeId',
            'messageId',
            'latitude',
            'longitude',
          }) &&
          _isNonEmptyString(params['worldId']) &&
          _isNonEmptyString(params['placeId']) &&
          (params['messageId'] == null ||
              _isNonEmptyString(params['messageId'])) &&
          params['latitude'] is num &&
          (params['latitude']! as num).isFinite &&
          (params['latitude']! as num) >= -90 &&
          (params['latitude']! as num) <= 90 &&
          params['longitude'] is num &&
          (params['longitude']! as num).isFinite &&
          (params['longitude']! as num) >= -180 &&
          (params['longitude']! as num) <= 180;
    case 'administratorInvitation':
      return _hasOnly(params, const {'worldId', 'token'}) &&
          _isNonEmptyString(params['worldId']) &&
          _isNonEmptyString(params['token']);
    case 'subscription':
      return params.isEmpty;
    default:
      return false;
  }
}

bool _hasOnly(Map<String, Object?> params, Set<String> allowed) =>
    params.keys.every(allowed.contains);

bool _isNonEmptyString(Object? value) => value is String && value.isNotEmpty;
