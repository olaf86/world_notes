import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/data/models/public_profile_model.dart';
import 'package:world_notes/data/repositories/follow_repository_impl.dart';

void main() {
  group('socialEdgeId', () {
    test('uses stable base64url tokens', () {
      expect(
        socialEdgeId(followerUid: 'alice', followeeUid: 'bob'),
        'YWxpY2U.Ym9i',
      );
    });

    test('does not collide when uids contain underscores', () {
      final first = socialEdgeId(followerUid: 'a_b', followeeUid: 'c');
      final second = socialEdgeId(followerUid: 'a', followeeUid: 'b_c');

      expect(first, isNot(second));
    });
  });

  group('PublicProfileModel', () {
    test('parses required profile fields', () {
      final model = PublicProfileModel.fromFirestoreData('user-1', {
        'displayName': 'Test User',
        'photoUrl': null,
        'followerCount': 0,
        'followingCount': 0,
      });

      expect(model.toEntity().displayName, 'Test User');
      expect(model.toEntity().followerCount, 0);
      expect(model.toEntity().followingCount, 0);
    });

    test('rejects a profile with missing counters', () {
      expect(
        () => PublicProfileModel.fromFirestoreData('user-1', {
          'displayName': 'Test User',
          'photoUrl': null,
        }),
        throwsA(isA<TypeError>()),
      );
    });
  });
}
