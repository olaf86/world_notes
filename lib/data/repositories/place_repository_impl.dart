import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../config/app_config.dart';
import '../../core/utils/geohash_util.dart';
import '../../domain/entities/place_entity.dart'
    show PlaceEntity, PlaceVisibility, ClosedReason, NoteMembership, NoteMember;
import '../../domain/repositories/place_repository.dart';
import '../models/place_model.dart';

// Required Firestore composite index:
//   Collection: places
//   Fields: geohash ASC, lastMessageAt DESC
class PlaceRepositoryImpl implements PlaceRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  PlaceRepositoryImpl({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  }) : _firestore = firestore,
       _functions = functions;

  CollectionReference get _places => _firestore.collection('places');

  /// Returns a query for one geohash cell ordered by most-recently-active.
  ///
  /// At precision 6, stored geohashes are exactly 6 chars, so
  /// `isEqualTo: prefix` is equivalent to the old range query — but allows
  /// a secondary orderBy without the "first orderBy must match range field"
  /// restriction. Required composite index: (geohash ASC, lastMessageAt DESC).
  Query _cellQuery(String prefix) => _places
      .where('geohash', isEqualTo: prefix)
      .orderBy('lastMessageAt', descending: true)
      .limit(AppConfig.placesPerCellLimit);

  @override
  Future<List<PlaceEntity>> getPlacesNearby({
    required double latitude,
    required double longitude,
  }) async {
    final prefixes = getGeohashPrefixes(
      latitude,
      longitude,
      precision: AppConfig.geohashPrecision,
    );

    final results = await Future.wait(
      prefixes.map((prefix) => _cellQuery(prefix).get()),
    );
    return _collectVisible(results);
  }

  /// Dedups documents across overlapping geohash cells and drops notes that
  /// should not appear in proximity search: archived (server-set) and expired
  /// (client-side gate until the archive Cloud Function runs).
  List<PlaceEntity> _collectVisible(List<QuerySnapshot> results) {
    final seen = <String>{};
    final places = <PlaceEntity>[];
    for (final snap in results) {
      for (final doc in snap.docs) {
        if (!seen.add(doc.id)) continue;
        final place = PlaceModel.fromFirestore(doc).toEntity();
        if (place.isArchived || place.isExpired) continue;
        places.add(place);
      }
    }
    return places;
  }

  @override
  Stream<List<PlaceEntity>> watchPlacesNearby({
    required double latitude,
    required double longitude,
  }) {
    final prefixes = getGeohashPrefixes(
      latitude,
      longitude,
      precision: AppConfig.geohashPrecision,
    );

    late final StreamController<List<PlaceEntity>> controller;
    final latest = List<QuerySnapshot?>.filled(prefixes.length, null);
    final subscriptions = <StreamSubscription<QuerySnapshot>>[];

    void emitIfReady() {
      if (latest.any((snap) => snap == null)) return;
      controller.add(_collectVisible(latest.cast<QuerySnapshot>()));
    }

    controller = StreamController<List<PlaceEntity>>(
      onListen: () {
        for (var i = 0; i < prefixes.length; i++) {
          subscriptions.add(
            _cellQuery(prefixes[i]).snapshots().listen((snap) {
              latest[i] = snap;
              emitIfReady();
            }, onError: controller.addError),
          );
        }
      },
      onCancel: () async {
        await Future.wait(subscriptions.map((sub) => sub.cancel()));
      },
    );

    return controller.stream;
  }

  @override
  Future<String> createNote({
    required double latitude,
    required double longitude,
    required String title,
    String? subtitle,
    required String colorHex,
    required String icon,
    required int expiryDays,
    PlaceVisibility visibility = PlaceVisibility.public,
  }) async {
    // All creation goes through the Cloud Function: it enforces the per-user
    // note cap in a transaction and computes the geohash server-side. Direct
    // client writes to `places` are denied by security rules.
    final callable = _functions.httpsCallable('createNote');
    final result = await callable.call<Map<String, dynamic>>({
      'latitude': latitude,
      'longitude': longitude,
      'title': title,
      'subtitle': subtitle,
      'colorHex': colorHex,
      'icon': icon,
      'expiryDays': expiryDays,
      'visibility': visibility.toJson(),
    });
    return result.data['placeId'] as String;
  }

  @override
  Future<PlaceEntity?> getPlace(String placeId) async {
    final doc = await _places.doc(placeId).get();
    if (!doc.exists) return null;
    return PlaceModel.fromFirestore(doc).toEntity();
  }

  @override
  Stream<PlaceEntity?> watchPlace(String placeId) {
    return _places
        .doc(placeId)
        .snapshots()
        .map(
          (doc) => doc.exists ? PlaceModel.fromFirestore(doc).toEntity() : null,
        );
  }

  // ── Ownership queries ─────────────────────────────────────────────────────

  @override
  Future<int> countUserActivePlaces(String userId) async {
    final snap = await _places
        .where('createdByUserId', isEqualTo: userId)
        .where('isArchived', isEqualTo: false)
        .count()
        .get();
    return snap.count ?? 0;
  }

  // ── Writability ───────────────────────────────────────────────────────────

  @override
  Future<void> closePlace(
    String placeId, {
    required ClosedReason reason,
  }) async {
    await _places.doc(placeId).update({
      'isOpen': false,
      'closedReason': reason.toJson(),
      'closedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> reopenPlace(String placeId) async {
    await _places.doc(placeId).update({
      'isOpen': true,
      'closedReason': FieldValue.delete(),
      'closedAt': FieldValue.delete(),
    });
  }

  // ── Private access ──────────────────────────────────────────────────────

  @override
  Future<void> setNotePassword({
    required String placeId,
    required String password,
    String? lockHint,
  }) async {
    await _functions
        .httpsCallable('setNotePassword')
        .call<Map<String, dynamic>>({
          'placeId': placeId,
          'password': password,
          'lockHint': lockHint,
        });
  }

  @override
  Future<void> unlockNote({
    required String placeId,
    required String password,
  }) async {
    await _functions.httpsCallable('unlockNote').call<Map<String, dynamic>>({
      'placeId': placeId,
      'password': password,
    });
  }

  @override
  Stream<NoteMembership?> watchMembership({
    required String placeId,
    required String userId,
  }) {
    return _places
        .doc(placeId)
        .collection('members')
        .doc(userId)
        .snapshots()
        .map((doc) {
          if (!doc.exists) return null;
          final data = doc.data()!;
          return NoteMembership(
            invited: data['invited'] as bool? ?? false,
            viaPasswordVersion: (data['viaPasswordVersion'] as int?) ?? -1,
          );
        });
  }

  // ── Invitations ───────────────────────────────────────────────────────────

  @override
  Future<String> createInviteLink(String placeId) async {
    final result = await _functions
        .httpsCallable('createInviteLink')
        .call<Map<String, dynamic>>({'placeId': placeId});
    return result.data['token'] as String;
  }

  @override
  Future<void> revokeInvite(String placeId) async {
    await _functions.httpsCallable('revokeInvite').call<Map<String, dynamic>>({
      'placeId': placeId,
    });
  }

  @override
  Future<void> revokeNoteAccess({
    required String placeId,
    required String userId,
  }) async {
    await _functions
        .httpsCallable('revokeNoteAccess')
        .call<Map<String, dynamic>>({'placeId': placeId, 'userId': userId});
  }

  @override
  Future<String> claimInvite(String token) async {
    final result = await _functions
        .httpsCallable('claimInvite')
        .call<Map<String, dynamic>>({'token': token});
    return result.data['placeId'] as String;
  }

  @override
  Stream<List<NoteMember>> watchMembers(String placeId) {
    return _places
        .doc(placeId)
        .collection('members')
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) {
            final data = doc.data();
            return NoteMember(
              userId: doc.id,
              displayName: data['displayName'] as String?,
              email: data['email'] as String?,
              invited: data['invited'] as bool? ?? false,
            );
          }).toList(),
        );
  }
}
