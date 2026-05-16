import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../config/app_config.dart';
import '../../core/utils/geohash_util.dart';
import '../../domain/entities/note_entity.dart';
import '../../domain/repositories/note_repository.dart';
import '../../domain/repositories/place_repository.dart';
import '../models/note_model.dart';
import '../models/place_model.dart';

class NoteRepositoryImpl implements NoteRepository {
  final FirebaseFirestore _firestore;
  final PlaceRepository _placeRepository;
  final _uuid = const Uuid();

  NoteRepositoryImpl({
    required FirebaseFirestore firestore,
    required PlaceRepository placeRepository,
  })  : _firestore = firestore,
        _placeRepository = placeRepository;

  CollectionReference get _notes => _firestore.collection('notes');

  @override
  Future<NoteEntity> createNote(String placeId) async {
    final id = _uuid.v4();
    final model = NoteModel(
      id: id,
      placeId: placeId,
      createdAt: DateTime.now(),
    );
    await _notes.doc(id).set(model.toFirestore());
    return model.toEntity();
  }

  @override
  Future<NoteEntity?> getNoteByPlaceId(String placeId) async {
    final snap = await _notes
        .where('placeId', isEqualTo: placeId)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    return NoteModel.fromFirestore(snap.docs.first).toEntity();
  }

  @override
  Future<NoteBoxEntity> createPlaceWithNote({
    required double latitude,
    required double longitude,
    required String title,
    String? subtitle,
    required String colorHex,
    required String icon,
    required String createdByUserId,
  }) async {
    final placeId = _uuid.v4();
    final noteId = _uuid.v4();

    final geohash = encodeGeohash(
      latitude,
      longitude,
      precision: AppConfig.geohashPrecision,
    );

    final placeModel = PlaceModel(
      id: placeId,
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

    final noteModel = NoteModel(
      id: noteId,
      placeId: placeId,
      createdAt: DateTime.now(),
    );

    final batch = _firestore.batch();
    batch.set(
      _firestore.collection('places').doc(placeId),
      placeModel.toFirestore(),
    );
    batch.set(
      _firestore.collection('notes').doc(noteId),
      noteModel.toFirestore(),
    );
    await batch.commit();

    return NoteBoxEntity(note: noteModel.toEntity(), place: placeModel.toEntity());
  }

  @override
  Future<List<NoteBoxEntity>> getNoteBoxesNearby({
    required double latitude,
    required double longitude,
    required double radiusKm,
  }) async {
    final places = await _placeRepository.getPlacesNearby(
      latitude: latitude,
      longitude: longitude,
      radiusKm: radiusKm,
    );

    final noteBoxes = await Future.wait(
      places.map((place) async {
        final note = await getNoteByPlaceId(place.id);
        if (note == null) return null;
        return NoteBoxEntity(note: note, place: place);
      }),
    );

    return noteBoxes.whereType<NoteBoxEntity>().toList();
  }

  @override
  Stream<List<NoteBoxEntity>> watchNoteBoxesNearby({
    required double latitude,
    required double longitude,
    required double radiusKm,
  }) {
    return _placeRepository
        .watchPlacesNearby(
          latitude: latitude,
          longitude: longitude,
          radiusKm: radiusKm,
        )
        .asyncMap((places) async {
      final noteBoxes = await Future.wait(
        places.map((place) async {
          final note = await getNoteByPlaceId(place.id);
          if (note == null) return null;
          return NoteBoxEntity(note: note, place: place);
        }),
      );
      return noteBoxes.whereType<NoteBoxEntity>().toList();
    });
  }
}
