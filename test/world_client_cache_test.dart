import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/config/bootstrap_world_catalog.dart';
import 'package:world_notes/config/world_catalog.dart';
import 'package:world_notes/services/world_firebase_clients.dart';

void main() {
  test('creates one client set per world and reuses it', () {
    var creationCount = 0;
    final cache = WorldClientCache<Object>((_) {
      creationCount += 1;
      return Object();
    });
    final asia = bootstrapWorldCatalog.requireWorld(asiaWorldId);
    final europe = bootstrapWorldCatalog.requireWorld(const WorldId('europe'));

    final firstAsiaClient = cache.forWorld(asia);
    final secondAsiaClient = cache.forWorld(asia);
    final europeClient = cache.forWorld(europe);

    expect(secondAsiaClient, same(firstAsiaClient));
    expect(europeClient, isNot(same(firstAsiaClient)));
    expect(creationCount, 2);
  });
}
