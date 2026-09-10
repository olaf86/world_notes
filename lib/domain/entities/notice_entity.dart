class NoticeEntity {
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

  const NoticeEntity({
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

  bool get isUnread => readAt == null;
  bool get isCritical => severity == 'critical';
  bool get isWarning => severity == 'warning';
}

class NoticeActionEntity {
  final String route;
  final Map<String, Object?> params;

  const NoticeActionEntity({required this.route, this.params = const {}});
}
