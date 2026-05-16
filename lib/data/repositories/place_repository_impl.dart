import 'package:async/async.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../config/app_config.dart';
import '../../core/utils/geohash_util.dart';
import '../../domain/entities/place_entity.dart';
import '../../domain/repositories/place_repository.dart';
import '../models/place_model.dart';

class PlaceRepositoryImpl implements PlaceRepository {
  final FirebaseFirestore _firestore;
  final _uuid = const Uuid();

  PlaceRepositoryImpl({required FirebaseFirestore firestore})
      : _firestore = firestore;

  CollectionReference get _places => _firestore.collection('places');

  @override
  Future<List<PlaceEntity>> getPlacesNearby({
    required double latitude,
    required double longitude,
    required double radiusKm,
  }) async {
    final prefixes = getGeohashPrefixes(
      latitude,
      longitude,
      radiusKm,
      precision: AppConfig.geohashPrecision,
    );

    final results = await Future.wait(
      prefixes.map((prefix) => _places
          .where('geohash', isGreaterThanOrEqualTo: prefix)
          .where('geohash', isLessThan: '${prefix}z')
          .get()),
    );

    final seen = <String>{};
    final places = <PlaceEntity>[];

    for (final snap in results) {
      for (final doc in snap.docs) {
        if (seen.contains(doc.id)) continue;
        seen.add(doc.id);
        final place = PlaceModel.fromFirestore(doc).toEntity();
        final dist = haversineDistance(
          latitude,
          longitude,
          place.latitude,
          place.longitude,
        );
        if (dist <= radiusKm) places.add(place);
      }
    }

    return places;
  }

  @override
  Stream<List<PlaceEntity>> watchPlacesNearby({
    required double latitude,
    required double longitude,
    required double radiusKm,
  }) {
    // Use the same 9-cell (center + 8 neighbours) query as getPlacesNearby.
    final prefixes = getGeohashPrefixes(
      latitude,
      longitude,
      radiusKm,
      precision: AppConfig.geohashPrecision,
    );

    // Merge 9 snapshot streams into one deduplicated list.
    final streams = prefixes.map((prefix) => _places
        .where('geohash', isGreaterThanOrEqualTo: prefix)
        .where('geohash', isLessThan: '${prefix}z')
        .snapshots());

    return StreamGroup.merge(streams).map((_) => null).asyncMap((_) async {
      // On any cell update, re-fetch all cells and merge.
      final results = await Future.wait(
        prefixes.map((prefix) => _places
            .where('geohash', isGreaterThanOrEqualTo: prefix)
            .where('geohash', isLessThan: '${prefix}z')
            .get()),
      );

      final seen = <String>{};
      final places = <PlaceEntity>[];
      for (final snap in results) {
        for (final doc in snap.docs) {
          if (seen.contains(doc.id)) continue;
          seen.add(doc.id);
          final place = PlaceModel.fromFirestore(doc).toEntity();
          final dist = haversineDistance(
            latitude, longitude, place.latitude, place.longitude,
          );
          if (dist <= radiusKm) places.add(place);
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
