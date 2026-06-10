import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../config/app_config.dart';
import '../../core/utils/geohash_util.dart';
import '../../domain/entities/place_entity.dart'
    show
        ClosedReason,
        NoteLockType,
        NoteMember,
        NoteMembership,
        PlaceEntity,
        PlaceVisibility;
import '../../domain/repositories/place_repository.dart';
import '../models/place_model.dart';

// Required Firestore composite indexes are declared in firestore.indexes.json.
class PlaceRepositoryImpl implements PlaceRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  PlaceRepositoryImpl({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  }) : _firestore = firestore,
       _functions = functions;

  CollectionReference get _places => _firestore.collection('places');

  /// Returns a query for one geohash cell.
  ///
  /// Public discovery is gated by:
  ///   * a short-lived coarse discovery grant (discoveryGeohash),
  ///   * publication window (publishAt/expiresAt),
  ///   * archive state,
  ///   * per-query result limit.
  ///
  /// The publish/expires filters are range filters on different fields. That
  /// is supported by Firestore only when the query can use the matching
  /// composite index, so keep these orderBy fields in sync with
  /// firestore.indexes.json.
  Query _cellQuery(String prefix, DateTime now) {
    // Firestore Rules compare against request.time, which is a little later
    // than the server time returned by the grant function. These buffers make
    // the query provably narrower than the rule window instead of occasionally
    // failing with permission-denied because of milliseconds of drift.
    final publishCutoff = now.subtract(const Duration(seconds: 5));
    final expiresCutoff = now.add(const Duration(seconds: 30));

    return _places
        .where('geohash', isEqualTo: prefix)
        .where(
          'discoveryGeohash',
          isEqualTo: prefix.substring(0, AppConfig.discoveryGeohashPrecision),
        )
        .where('isArchived', isEqualTo: false)
        .where(
          'publishAt',
          isLessThanOrEqualTo: Timestamp.fromDate(publishCutoff),
        )
        .where('expiresAt', isGreaterThan: Timestamp.fromDate(expiresCutoff))
        .orderBy('publishAt')
        .orderBy('expiresAt')
        .limit(AppConfig.placesPerCellLimit);
  }

  @override
  Future<List<PlaceEntity>> getPlacesNearby({
    required double latitude,
    required double longitude,
    required DateTime now,
  }) async {
    final prefixes = getGeohashPrefixes(
      latitude,
      longitude,
      precision: AppConfig.geohashPrecision,
    );

    final results = await Future.wait(
      prefixes.map((prefix) => _cellQuery(prefix, now).get()),
    );
    return _collectVisible(results, now);
  }

  /// Dedups documents across overlapping geohash cells and drops notes that
  /// should not appear in proximity search.
  List<PlaceEntity> _collectVisible(List<QuerySnapshot> results, DateTime now) {
    final seen = <String>{};
    final places = <PlaceEntity>[];
    for (final snap in results) {
      for (final doc in snap.docs) {
        if (!seen.add(doc.id)) continue;
        final place = PlaceModel.fromFirestore(doc).toEntity();
        if (!place.isDiscoverableAt(now)) continue;
        places.add(place);
      }
    }
    places.sort((a, b) {
      final aTime = a.lastMessageAt ?? a.createdAt;
      final bTime = b.lastMessageAt ?? b.createdAt;
      return bTime.compareTo(aTime);
    });
    return places;
  }

  @override
  Stream<List<PlaceEntity>> watchPlacesNearby({
    required double latitude,
    required double longitude,
    required DateTime now,
  }) {
    final prefixes = getGeohashPrefixes(
      latitude,
      longitude,
      precision: AppConfig.geohashPrecision,
    );

    late final StreamController<List<PlaceEntity>> controller;
    final latest = List<QuerySnapshot?>.filled(prefixes.length, null);
    final subscriptions = <StreamSubscription<QuerySnapshot>>[];

    void emitLatest() {
      final ready = latest.whereType<QuerySnapshot>().toList();
      if (ready.isEmpty) return;
      controller.add(_collectVisible(ready, now));
    }

    controller = StreamController<List<PlaceEntity>>(
      onListen: () {
        for (var i = 0; i < prefixes.length; i++) {
          subscriptions.add(
            _cellQuery(prefixes[i], now).snapshots().listen((snap) {
              latest[i] = snap;
              emitLatest();
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
  Future<DiscoveryGrant> ensureDiscoveryGrant({
    required double latitude,
    required double longitude,
  }) async {
    final result = await _functions
        .httpsCallable('ensureDiscoveryGrant')
        .call<Map<String, dynamic>>({
          'latitude': latitude,
          'longitude': longitude,
        });
    final data = result.data;
    final expiresAtMillis = data['expiresAtMillis'] as int;
    return DiscoveryGrant(
      discoveryGeohashes: (data['discoveryGeohashes'] as List<dynamic>)
          .whereType<String>()
          .toList(),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMillis),
      serverNowMillis: data['serverNowMillis'] as int,
    );
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
    DateTime? publishAt,
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
      if (publishAt != null)
        'publishAtMillis': publishAt.millisecondsSinceEpoch,
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

  Query _ownedPlacesQuery(String userId) => _places
      .where('ownerIds', arrayContains: userId)
      .where('isArchived', isEqualTo: false);

  List<PlaceEntity> _collectMyPlaces(QuerySnapshot snap) {
    final places = snap.docs
        .map((doc) => PlaceModel.fromFirestore(doc).toEntity())
        .where((place) => !place.isArchived && !place.isExpired)
        .toList();
    places.sort((a, b) {
      final aTime = a.lastMessageAt ?? a.createdAt;
      final bTime = b.lastMessageAt ?? b.createdAt;
      return bTime.compareTo(aTime);
    });
    return places;
  }

  @override
  Future<int> countUserActivePlaces(String userId) async {
    final snap = await _places
        .where('ownerIds', arrayContains: userId)
        .where('isArchived', isEqualTo: false)
        .count()
        .get();
    return snap.count ?? 0;
  }

  @override
  Stream<List<PlaceEntity>> watchMyPlaces(String userId) {
    return _ownedPlacesQuery(userId).snapshots().map(_collectMyPlaces);
  }

  @override
  Future<List<PlaceEntity>> getMyPlaces(String userId) async {
    final snap = await _ownedPlacesQuery(userId).get();
    return _collectMyPlaces(snap);
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
    required NoteLockType lockType,
    String? lockHint,
  }) async {
    await _functions
        .httpsCallable('setNotePassword')
        .call<Map<String, dynamic>>({
          'placeId': placeId,
          'password': password,
          'lockType': lockType.toJson(),
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
