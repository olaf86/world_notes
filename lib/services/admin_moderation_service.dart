import 'package:uuid/uuid.dart';

import 'world_firebase_clients.dart';

import '../domain/entities/admin_account_safety_entity.dart';
import '../domain/entities/admin_moderation_review_entity.dart';
import 'global_operation_observer.dart';

const defaultAdminModerationReviewListLimit = 20;

final class AdminModerationService {
  final WorldFunctionsClient _functions;
  final GlobalOperationObserver? _operationObserver;
  final Uuid _uuid;

  AdminModerationService({
    required WorldFunctionsClient functions,
    required GlobalOperationObserver? operationObserver,
    Uuid uuid = const Uuid(),
  }) : _functions = functions,
       _operationObserver = operationObserver,
       _uuid = uuid;

  Future<List<AdminModerationReviewEntity>> listReviews({
    required AdminModerationReviewStatus status,
    int limit = defaultAdminModerationReviewListLimit,
  }) async {
    final result = await _functions
        .httpsCallable('adminListModerationReviews')
        .call<Map<String, dynamic>>({'status': status.name, 'limit': limit});
    final data = result.data;
    final reviews = data['reviews'];
    if (reviews is! List) return const [];
    return reviews
        .whereType<Map>()
        .map((item) => AdminModerationReviewEntity.fromJson(_stringKeyed(item)))
        .toList(growable: false);
  }

  Future<void> reviewContent({
    required AdminModerationTargetType targetType,
    required String placeId,
    required String targetId,
    required AdminModerationAction action,
    String? reason,
  }) async {
    final callableName = targetType == AdminModerationTargetType.note
        ? 'adminReviewNote'
        : 'adminReviewMessage';
    await _functions.httpsCallable(callableName).call<Map<String, dynamic>>({
      'placeId': placeId,
      if (targetType == AdminModerationTargetType.message)
        'messageId': targetId,
      'action': action.name,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
  }

  Future<AdminAccountSafetyEntity> getAccountSafety({
    required String targetUid,
    int auditLimit = defaultAdminModerationReviewListLimit,
  }) async {
    final result = await _functions
        .httpsCallable('adminGetAccountSafety')
        .call<Map<String, dynamic>>({
          'targetUid': targetUid,
          'auditLimit': auditLimit,
        });
    return AdminAccountSafetyEntity.fromJson(result.data);
  }

  Future<AdminAccountSafetyUpdateResult> updateAccountSafety({
    required String targetUid,
    required AdminAccountSafetyAction action,
    required String reason,
    String? reference,
  }) async {
    final result = await _functions
        .httpsCallable('adminUpdateAccountSafety')
        .call<Map<String, dynamic>>({
          'targetUid': targetUid,
          'operationId': _uuid.v7(),
          'action': action.toJson(),
          'reason': reason.trim(),
          if (reference != null && reference.trim().isNotEmpty)
            'reference': reference.trim(),
        });
    final operation = await handleAcceptedGlobalOperation(
      response: result.data,
      policy: GlobalOperationObservationPolicy.durable,
      observer: _operationObserver,
    );
    final revision = result.data['revision'];
    if (revision is! int || revision <= 0) {
      throw const FormatException('Account safety revision is invalid.');
    }
    return AdminAccountSafetyUpdateResult(
      operation: operation,
      revision: revision,
    );
  }
}

Map<String, dynamic> _stringKeyed(Map<dynamic, dynamic> map) {
  return map.map((key, value) => MapEntry(key.toString(), value));
}
