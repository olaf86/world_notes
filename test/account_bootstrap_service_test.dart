import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/config/bootstrap_world_catalog.dart';
import 'package:world_notes/config/world_catalog.dart';
import 'package:world_notes/services/account_bootstrap_service.dart';

void main() {
  test('parses a catalogued immutable home assignment', () {
    final assignment = HomeAssignment.fromData(const {
      'world': 'asia',
      'epoch': 1,
    }, bootstrapWorldCatalog);

    expect(assignment, const HomeAssignment(homeWorld: asiaWorldId, epoch: 1));
  });

  test('rejects unknown worlds and invalid epochs', () {
    expect(
      () => HomeAssignment.fromData(const {
        'world': 'unknown',
        'epoch': 1,
      }, bootstrapWorldCatalog),
      throwsStateError,
    );
    expect(
      () => HomeAssignment.fromData(const {
        'world': 'asia',
        'epoch': 0,
      }, bootstrapWorldCatalog),
      throwsA(isA<FormatException>()),
    );
  });

  test('keeps home identity and epoch in equality', () {
    expect(
      const HomeAssignment(homeWorld: asiaWorldId, epoch: 1),
      isNot(const HomeAssignment(homeWorld: WorldId('asia'), epoch: 2)),
    );
  });
}
