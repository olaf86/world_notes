import 'global_operation_entity.dart';

enum AdminAccountSafetyActionType {
  adjustPoints,
  setRestriction,
  clearRestriction,
  setBan,
  setPermanentBan,
  clearBan,
}

final class AdminAccountSafetyAction {
  const AdminAccountSafetyAction._(this.type, this.value);

  const AdminAccountSafetyAction.adjustPoints(int delta)
    : this._(AdminAccountSafetyActionType.adjustPoints, delta);

  const AdminAccountSafetyAction.setRestriction(int days)
    : this._(AdminAccountSafetyActionType.setRestriction, days);

  const AdminAccountSafetyAction.clearRestriction()
    : this._(AdminAccountSafetyActionType.clearRestriction, null);

  const AdminAccountSafetyAction.setBan(int days)
    : this._(AdminAccountSafetyActionType.setBan, days);

  const AdminAccountSafetyAction.setPermanentBan()
    : this._(AdminAccountSafetyActionType.setPermanentBan, null);

  const AdminAccountSafetyAction.clearBan()
    : this._(AdminAccountSafetyActionType.clearBan, null);

  final AdminAccountSafetyActionType type;
  final int? value;

  Map<String, dynamic> toJson() => switch (type) {
    AdminAccountSafetyActionType.adjustPoints => {
      'type': type.name,
      'delta': value,
    },
    AdminAccountSafetyActionType.setRestriction ||
    AdminAccountSafetyActionType.setBan => {
      'type': type.name,
      'durationDays': value,
    },
    _ => {'type': type.name},
  };
}

final class AdminAccountSafetyAuditEntity {
  const AdminAccountSafetyAuditEntity({
    required this.operationId,
    required this.adminUid,
    required this.action,
    required this.reason,
    required this.reference,
    required this.revision,
    required this.createdAt,
  });

  factory AdminAccountSafetyAuditEntity.fromJson(Map<String, dynamic> json) {
    return AdminAccountSafetyAuditEntity(
      operationId: _requiredString(json['operationId'], 'operationId'),
      adminUid: _requiredString(json['adminUid'], 'adminUid'),
      action: _requiredMap(json['action'], 'action'),
      reason: _requiredString(json['reason'], 'reason'),
      reference: _nullableString(json['reference'], 'reference'),
      revision: _positiveInt(json['revision'], 'revision'),
      createdAt: _requiredDate(json['createdAtMillis'], 'createdAtMillis'),
    );
  }

  final String operationId;
  final String adminUid;
  final Map<String, dynamic> action;
  final String reason;
  final String? reference;
  final int revision;
  final DateTime createdAt;
}

final class AdminAccountSafetyEntity {
  const AdminAccountSafetyEntity({
    required this.targetUid,
    required this.authorityWorld,
    required this.revision,
    required this.violationPoints,
    required this.lastViolationAt,
    required this.nextPointDecayAt,
    required this.restrictedUntil,
    required this.bannedUntil,
    required this.isPermanentlyBanned,
    required this.updatedAt,
    required this.audits,
  });

  factory AdminAccountSafetyEntity.fromJson(Map<String, dynamic> json) {
    final audits = json['audits'];
    if (audits is! List) {
      throw const FormatException('Account safety audits are invalid.');
    }
    if (audits.any((value) => value is! Map)) {
      throw const FormatException('Account safety audit entry is invalid.');
    }
    return AdminAccountSafetyEntity(
      targetUid: _requiredString(json['targetUid'], 'targetUid'),
      authorityWorld: _requiredString(json['authorityWorld'], 'authorityWorld'),
      revision: _positiveInt(json['revision'], 'revision'),
      violationPoints: _points(json['violationPoints']),
      lastViolationAt: _nullableDate(
        json['lastViolationAtMillis'],
        'lastViolationAtMillis',
      ),
      nextPointDecayAt: _nullableDate(
        json['nextPointDecayAtMillis'],
        'nextPointDecayAtMillis',
      ),
      restrictedUntil: _nullableDate(
        json['restrictedUntilMillis'],
        'restrictedUntilMillis',
      ),
      bannedUntil: _nullableDate(
        json['bannedUntilMillis'],
        'bannedUntilMillis',
      ),
      isPermanentlyBanned: _requiredBool(
        json['isPermanentlyBanned'],
        'isPermanentlyBanned',
      ),
      updatedAt: _requiredDate(json['updatedAtMillis'], 'updatedAtMillis'),
      audits: List.unmodifiable(
        audits.cast<Map>().map(
          (value) =>
              AdminAccountSafetyAuditEntity.fromJson(_stringKeyed(value)),
        ),
      ),
    );
  }

  final String targetUid;
  final String authorityWorld;
  final int revision;
  final int violationPoints;
  final DateTime? lastViolationAt;
  final DateTime? nextPointDecayAt;
  final DateTime? restrictedUntil;
  final DateTime? bannedUntil;
  final bool isPermanentlyBanned;
  final DateTime updatedAt;
  final List<AdminAccountSafetyAuditEntity> audits;
}

final class AdminAccountSafetyUpdateResult {
  const AdminAccountSafetyUpdateResult({
    required this.operation,
    required this.revision,
  });

  final GlobalOperationReference operation;
  final int revision;
}

Map<String, dynamic> _stringKeyed(Map<dynamic, dynamic> map) {
  return map.map((key, value) => MapEntry(key.toString(), value));
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw FormatException('Account safety $field is invalid.');
  }
  return value;
}

String? _nullableString(Object? value, String field) {
  if (value == null) return null;
  return _requiredString(value, field);
}

Map<String, dynamic> _requiredMap(Object? value, String field) {
  if (value is! Map) {
    throw FormatException('Account safety $field is invalid.');
  }
  return _stringKeyed(value);
}

int _positiveInt(Object? value, String field) {
  if (value is! int || value <= 0) {
    throw FormatException('Account safety $field is invalid.');
  }
  return value;
}

int _points(Object? value) {
  if (value is! int || value < 0 || value > 100) {
    throw const FormatException('Account safety points are invalid.');
  }
  return value;
}

bool _requiredBool(Object? value, String field) {
  if (value is! bool) {
    throw FormatException('Account safety $field is invalid.');
  }
  return value;
}

DateTime _requiredDate(Object? value, String field) {
  if (value is! int || value < 0) {
    throw FormatException('Account safety $field is invalid.');
  }
  return DateTime.fromMillisecondsSinceEpoch(value);
}

DateTime? _nullableDate(Object? value, String field) {
  if (value == null) return null;
  return _requiredDate(value, field);
}
