import '../entities/place_entity.dart';

abstract class PlaceRepository {
  Future<List<PlaceEntity>> getPlacesNearby({
    required double latitude,
    required double longitude,
  });

  Stream<List<PlaceEntity>> watchPlacesNearby({
    required double latitude,
    required double longitude,
  });

  Future<PlaceEntity> createPlace({
    required double latitude,
    required double longitude,
    required String title,
    String? subtitle,
    required String colorHex,
    required String icon,
    required String createdByUserId,
  });

  Future<PlaceEntity?> getPlace(String placeId);
}
