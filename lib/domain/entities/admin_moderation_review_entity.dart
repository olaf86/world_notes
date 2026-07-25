enum AdminModerationReviewStatus { open, resolved }

enum AdminModerationAction { allow, sensitive, hidden }

enum AdminModerationTargetType {
  message,
  note;

  static AdminModerationTargetType fromJson(Object? value) => switch (value) {
    'message' => message,
    'note' => note,
    _ => throw const FormatException('Invalid moderation target type.'),
  };
}

class AdminModerationRiskSignal {
  final String category;
  final String severity;
  final bool reviewRecommended;

  const AdminModerationRiskSignal({
    required this.category,
    required this.severity,
    required this.reviewRecommended,
  });

  factory AdminModerationRiskSignal.fromJson(Map<String, dynamic> json) {
    return AdminModerationRiskSignal(
      category: json['category'] as String? ?? 'unknown',
      severity: json['severity'] as String? ?? 'unknown',
      reviewRecommended: json['reviewRecommended'] == true,
    );
  }
}

class AdminModerationReviewEntity {
  final String id;
  final AdminModerationTargetType targetType;
  final String targetId;
  final String targetPath;
  final String? userId;
  final String placeId;
  final String content;
  final List<String> imageStoragePaths;
  final String status;
  final List<String> reviewSources;
  final int? reportCount;
  final List<String> reportReasonsSummary;
  final List<AdminModerationRiskSignal> riskSignals;
  final String? action;
  final double? maxScore;
  final List<String> categories;
  final String? provider;
  final String? providerModel;
  final String? policyVersion;
  final bool? flagged;
  final DateTime? createdAt;
  final DateTime? checkedAt;
  final String? humanDecision;
  final String? decisionReason;
  final DateTime? reviewedAt;
  final String? reviewedBy;

  const AdminModerationReviewEntity({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.targetPath,
    required this.userId,
    required this.placeId,
    required this.content,
    required this.imageStoragePaths,
    required this.status,
    required this.reviewSources,
    required this.reportCount,
    required this.reportReasonsSummary,
    required this.riskSignals,
    required this.action,
    required this.maxScore,
    required this.categories,
    required this.provider,
    required this.providerModel,
    required this.policyVersion,
    required this.flagged,
    required this.createdAt,
    required this.checkedAt,
    required this.humanDecision,
    required this.decisionReason,
    required this.reviewedAt,
    required this.reviewedBy,
  });

  factory AdminModerationReviewEntity.fromJson(Map<String, dynamic> json) {
    return AdminModerationReviewEntity(
      id: json['id'] as String? ?? '',
      targetType: AdminModerationTargetType.fromJson(json['targetType']),
      targetId: json['targetId'] as String,
      targetPath: json['targetPath'] as String,
      userId: json['userId'] as String?,
      placeId: json['placeId'] as String,
      content: json['content'] as String? ?? '',
      imageStoragePaths: _stringList(json['imageStoragePaths']),
      status: json['status'] as String? ?? 'open',
      reviewSources: _stringList(json['reviewSources']),
      reportCount: _int(json['reportCount']),
      reportReasonsSummary: _stringList(json['reportReasonsSummary']),
      riskSignals: _riskSignals(json['riskSignals']),
      action: json['action'] as String?,
      maxScore: _double(json['maxScore']),
      categories: _stringList(json['categories']),
      provider: json['provider'] as String?,
      providerModel: json['providerModel'] as String?,
      policyVersion: json['policyVersion'] as String?,
      flagged: json['flagged'] as bool?,
      createdAt: _dateTime(json['createdAtMillis']),
      checkedAt: _dateTime(json['checkedAtMillis']),
      humanDecision: json['humanDecision'] as String?,
      decisionReason: json['decisionReason'] as String?,
      reviewedAt: _dateTime(json['reviewedAtMillis']),
      reviewedBy: json['reviewedBy'] as String?,
    );
  }

  bool get hasImages => imageStoragePaths.isNotEmpty;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}

List<AdminModerationRiskSignal> _riskSignals(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => AdminModerationRiskSignal.fromJson(_stringKeyed(item)))
      .toList(growable: false);
}

Map<String, dynamic> _stringKeyed(Map<dynamic, dynamic> map) {
  return map.map((key, value) => MapEntry(key.toString(), value));
}

double? _double(Object? value) {
  if (value is int) return value.toDouble();
  if (value is double) return value;
  return null;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is double) return value.round();
  return null;
}

DateTime? _dateTime(Object? millis) {
  if (millis is int) return DateTime.fromMillisecondsSinceEpoch(millis);
  if (millis is double) {
    return DateTime.fromMillisecondsSinceEpoch(millis.round());
  }
  return null;
}
