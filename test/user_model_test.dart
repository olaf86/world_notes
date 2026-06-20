import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/data/models/user_model.dart';

void main() {
  group('UserModel', () {
    test('reads displayName', () {
      final model = UserModel.fromFirestoreData('uid-1', {
        'displayName': 'Nickname',
        'email': 'user@example.com',
        'photoUrl': 'https://example.com/photo.png',
        'isPremium': true,
      });

      expect(model.name, 'Nickname');
      expect(model.email, 'user@example.com');
      expect(model.photoUrl, 'https://example.com/photo.png');
      expect(model.isPremium, isTrue);
    });

    test('writes displayName field', () {
      final model = UserModel(id: 'uid-1', name: 'Nickname');

      expect(model.toFirestore(), containsPair('displayName', 'Nickname'));
      expect(model.toFirestore(), isNot(contains('name')));
      expect(model.toFirestore(), isNot(contains('isPremium')));
    });
  });
}
