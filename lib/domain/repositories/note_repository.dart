import '../entities/note_entity.dart';

abstract class NoteRepository {
  Future<NoteEntity> createNote(String placeId);
  Future<NoteEntity?> getNoteByPlaceId(String placeId);
  Future<List<NoteBoxEntity>> getNoteBoxesNearby({
    required double latitude,
    required double longitude,
    required double radiusKm,
  });
  Stream<List<NoteBoxEntity>> watchNoteBoxesNearby({
    required double latitude,
    required double longitude,
    required double radiusKm,
  });
}
