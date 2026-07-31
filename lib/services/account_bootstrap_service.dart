import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/world_catalog.dart';
import 'world_firebase_clients.dart';

/// Immutable routing assignment read from `userHomes/{uid}`.
final class HomeAssignment {
  const HomeAssignment({required this.homeWorld, required this.epoch});

  final WorldId homeWorld;
  final int epoch;

  factory HomeAssignment.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    WorldCatalog catalog,
  ) {
    final data = snapshot.data();
    if (data == null) {
      throw StateError('Home assignment is missing.');
    }
    return HomeAssignment.fromData(data, catalog);
  }

  factory HomeAssignment.fromData(
    Map<String, dynamic> data,
    WorldCatalog catalog,
  ) {
    final world = data['world'];
    final epoch = data['epoch'];
    if (world is! String || epoch is! int || epoch <= 0) {
      throw const FormatException('Home assignment fields are invalid.');
    }
    final homeWorld = WorldId(world);
    catalog.requireWorld(homeWorld);
    return HomeAssignment(homeWorld: homeWorld, epoch: epoch);
  }

  @override
  bool operator ==(Object other) {
    return other is HomeAssignment &&
        other.homeWorld == homeWorld &&
        other.epoch == epoch;
  }

  @override
  int get hashCode => Object.hash(homeWorld, epoch);
}

/// Reads the bootstrap directory and invokes its trusted assignment command.
final class AccountBootstrapService {
  const AccountBootstrapService({
    required FirebaseFirestore directoryFirestore,
    required WorldFunctionsClient directoryFunctions,
    required WorldCatalog catalog,
  }) : _directoryFirestore = directoryFirestore,
       _directoryFunctions = directoryFunctions,
       _catalog = catalog;

  final FirebaseFirestore _directoryFirestore;
  final WorldFunctionsClient _directoryFunctions;
  final WorldCatalog _catalog;

  Stream<HomeAssignment?> watchHome(String uid) {
    return _directoryFirestore
        .collection('userHomes')
        .doc(uid)
        .snapshots()
        .map(
          (snapshot) => snapshot.exists
              ? HomeAssignment.fromFirestore(snapshot, _catalog)
              : null,
        );
  }

  Future<HomeAssignment> assignHome(WorldId homeWorld) async {
    _catalog.requireHomeWorld(homeWorld);
    final response = await _directoryFunctions
        .httpsCallable('assignHomeWorld')
        .call<Map<String, dynamic>>({'homeWorld': homeWorld.value});
    final data = response.data;
    final returnedWorld = data['homeWorld'];
    final epoch = data['epoch'];
    final ready = data['ready'];
    if (returnedWorld != homeWorld.value ||
        epoch is! int ||
        epoch <= 0 ||
        ready != true) {
      throw StateError('Account bootstrap response is invalid.');
    }
    return HomeAssignment(homeWorld: homeWorld, epoch: epoch);
  }

  Future<bool> isWorldReady({
    required String uid,
    required HomeAssignment assignment,
    required FirebaseFirestore destination,
  }) async {
    final marker = await destination.collection('userHomes').doc(uid).get();
    if (!marker.exists) return false;
    final installed = HomeAssignment.fromFirestore(marker, _catalog);
    return installed == assignment;
  }
}
