import 'package:cloud_functions/cloud_functions.dart';

import '../domain/entities/admin_moderation_review_entity.dart';

const defaultAdminModerationReviewListLimit = 20;

class AdminModerationService {
  final FirebaseFunctions _functions;

  const AdminModerationService({required FirebaseFunctions functions})
    : _functions = functions;

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
}

Map<String, dynamic> _stringKeyed(Map<dynamic, dynamic> map) {
  return map.map((key, value) => MapEntry(key.toString(), value));
}
