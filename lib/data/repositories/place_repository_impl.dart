import 'package:async/async.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../config/app_config.dart';
import '../../core/utils/geohash_util.dart';
import '../../domain/entities/place_entity.dart';
import '../../domain/repositories/place_repository.dart';
import '../models/place_model.dart';

// Required Firestore composite index:
//   Collection: places
//   Fields: geohash ASC, lastMessageAt DESC
class PlaceRepositoryImpl implements PlaceRepository {
  final FirebaseFirestore _firestore;
  final _uuid = const Uuid();

  PlaceRepositoryImpl({required FirebaseFirestore firestore})
      : _firestore = firestore;

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

    final seen = <String>{};
    final places = <PlaceEntity>[];
    for (final snap in results) {
      for (final doc in snap.docs) {
        if (seen.add(doc.id)) {
          places.add(PlaceModel.fromFirestore(doc).toEntity());
        }
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

    final streams = prefixes.map((prefix) => _cellQuery(prefix).snapshots());

    return StreamGroup.merge(streams).map((_) => null).asyncMap((_) async {
      final results = await Future.wait(
        prefixes.map((prefix) => _cellQuery(prefix).get()),
      );

      final seen = <String>{};
      final places = <PlaceEntity>[];
      for (final snap in results) {
        for (final doc in snap.docs) {
          if (seen.add(doc.id)) {
            places.add(PlaceModel.fromFirestore(doc).toEntity());
          }
        }
      }
      return places;
    });
  }

  @override
  Future<PlaceEntity> createPlace({
    required double latitude,
    required double longitude,
    required String title,
    String? subtitle,
    required String colorHex,
    required String icon,
    required String createdByUserId,
  }) async {
    final id = _uuid.v4();
    final geohash = encodeGeohash(
      latitude,
      longitude,
      precision: AppConfig.geohashPrecision,
    );

    final model = PlaceModel(
      id: id,
      latitude: latitude,
      longitude: longitude,
      geohash: geohash,
      title: title,
      subtitle: subtitle,
      colorHex: colorHex,
      icon: icon,
      createdByUserId: createdByUserId,
      createdAt: DateTime.now(),
      messageCount: 0,
      // lastMessageAt is null → toFirestore() writes serverTimestamp() so new
      // places sort among themselves by creation time until first message.
    );

    await _places.doc(id).set(model.toFirestore());
    return model.toEntity();
  }

  @override
  Future<PlaceEntity?> getPlace(String placeId) async {
    final doc = await _places.doc(placeId).get();
    if (!doc.exists) return null;
    return PlaceModel.fromFirestore(doc).toEntity();
  }
}
