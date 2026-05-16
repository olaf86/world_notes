import '../entities/note_entity.dart';

abstract class NoteRepository {
  Future<NoteEntity> createNote(String placeId);
  Future<NoteEntity?> getNoteByPlaceId(String placeId);

  /// Creates a place and its associated note in a single atomic batch write,
  /// eliminating the window where a place exists without a note.
  Future<NoteBoxEntity> createPlaceWithNote({
    required double latitude,
    required double longitude,
    required String title,
    String? subtitle,
    required String colorHex,
    required String icon,
    required String createdByUserId,
  });

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
