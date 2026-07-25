import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/admin_moderation_review_entity.dart';

void main() {
  group('AdminModerationReviewEntity', () {
    test('parses callable review data', () {
      final review = AdminModerationReviewEntity.fromJson({
        'id': 'place-1_message-1',
        'userId': 'user-1',
        'placeId': 'place-1',
        'messageId': 'message-1',
        'content': 'hello',
        'imageStoragePaths': ['a.webp'],
        'status': 'open',
        'reviewSources': ['provider', 'riskSignal', 'userReport'],
        'reportCount': 3,
        'reportReasonsSummary': ['Spam or advertising'],
        'riskSignals': [
          {'category': 'email', 'severity': 'high', 'reviewRecommended': true},
        ],
        'action': 'pending',
        'maxScore': 0.92,
        'categories': ['harassment'],
        'provider': 'openai',
        'providerModel': 'omni-moderation-latest',
        'policyVersion': '2026-01-01',
        'flagged': true,
        'createdAtMillis': 1710000000000,
      });

      expect(review.id, 'place-1_message-1');
      expect(review.targetType, AdminModerationTargetType.message);
      expect(review.canReview, isTrue);
      expect(review.reviewSources, ['provider', 'riskSignal', 'userReport']);
      expect(review.reportCount, 3);
      expect(review.reportReasonsSummary, ['Spam or advertising']);
      expect(review.riskSignals.single.category, 'email');
      expect(review.maxScore, 0.92);
      expect(review.hasImages, isTrue);
      expect(
        review.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1710000000000),
      );
    });

    test('parses a note review without a message id', () {
      final review = AdminModerationReviewEntity.fromJson({
        'id': 'note_place-1',
        'targetType': 'note',
        'targetId': 'place-1',
        'targetPath': 'places/place-1',
        'placeId': 'place-1',
        'content': 'Title\nDescription',
        'status': 'open',
      });

      expect(review.targetType, AdminModerationTargetType.note);
      expect(review.targetId, 'place-1');
      expect(review.messageId, isNull);
      expect(review.canReview, isTrue);
    });

    test('uses safe defaults for partial data', () {
      final review = AdminModerationReviewEntity.fromJson({'id': 'review-1'});

      expect(review.id, 'review-1');
      expect(review.content, '');
      expect(review.status, 'open');
      expect(review.reviewSources, isEmpty);
      expect(review.reportCount, isNull);
      expect(review.reportReasonsSummary, isEmpty);
      expect(review.riskSignals, isEmpty);
      expect(review.canReview, isFalse);
    });
  });
}
