import 'package:cloud_functions/cloud_functions.dart';

import '../domain/entities/admin_moderation_review_entity.dart';

class AdminModerationService {
  final FirebaseFunctions _functions;

  const AdminModerationService({required FirebaseFunctions functions})
    : _functions = functions;

  Future<List<AdminModerationReviewEntity>> listReviews({
    required AdminModerationReviewStatus status,
    int limit = 20,
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

  Future<void> reviewMessage({
    required String placeId,
    required String messageId,
    required AdminModerationAction action,
    String? reason,
  }) async {
    await _functions
        .httpsCallable('adminReviewMessage')
        .call<Map<String, dynamic>>({
          'placeId': placeId,
          'messageId': messageId,
          'action': action.name,
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
        });
  }
}

Map<String, dynamic> _stringKeyed(Map<dynamic, dynamic> map) {
  return map.map((key, value) => MapEntry(key.toString(), value));
}
