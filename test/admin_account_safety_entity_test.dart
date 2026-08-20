import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/admin_account_safety_entity.dart';

void main() {
  test('parses account safety state and audit history', () {
    final entity = AdminAccountSafetyEntity.fromJson({
      'targetUid': 'test-target-user',
      'authorityWorld': 'europe',
      'revision': 4,
      'violationPoints': 75,
      'lastViolationAtMillis': 1000,
      'nextPointDecayAtMillis': 2000,
      'restrictedUntilMillis': 3000,
      'bannedUntilMillis': null,
      'isPermanentlyBanned': false,
      'updatedAtMillis': 4000,
      'audits': [
        {
          'operationId': 'test-admin-operation',
          'adminUid': 'test-admin-user',
          'action': {'type': 'setRestriction', 'durationDays': 3},
          'reason': 'Repeated confirmed violations',
          'reference': 'review:test-review',
          'revision': 4,
          'createdAtMillis': 4000,
        },
      ],
    });

    expect(entity.targetUid, 'test-target-user');
    expect(entity.authorityWorld, 'europe');
    expect(entity.violationPoints, 75);
    expect(entity.restrictedUntil?.millisecondsSinceEpoch, 3000);
    expect(entity.audits.single.action, {
      'type': 'setRestriction',
      'durationDays': 3,
    });
  });

  test('serializes only supported administrator action fields', () {
    expect(const AdminAccountSafetyAction.adjustPoints(-25).toJson(), {
      'type': 'adjustPoints',
      'delta': -25,
    });
    expect(const AdminAccountSafetyAction.setRestriction(7).toJson(), {
      'type': 'setRestriction',
      'durationDays': 7,
    });
    expect(const AdminAccountSafetyAction.setPermanentBan().toJson(), {
      'type': 'setPermanentBan',
    });
  });

  test('rejects malformed account safety payloads', () {
    expect(
      () => AdminAccountSafetyEntity.fromJson({
        'targetUid': 'test-target-user',
        'authorityWorld': 'asia',
        'revision': 1,
        'violationPoints': 101,
        'lastViolationAtMillis': null,
        'nextPointDecayAtMillis': null,
        'restrictedUntilMillis': null,
        'bannedUntilMillis': null,
        'isPermanentlyBanned': false,
        'updatedAtMillis': 1000,
        'audits': const [],
      }),
      throwsFormatException,
    );
  });
}
