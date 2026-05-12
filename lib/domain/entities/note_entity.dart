import 'place_entity.dart';

class NoteEntity {
  final String id;
  final String placeId;
  final DateTime createdAt;
  final int messageCount;

  const NoteEntity({
    required this.id,
    required this.placeId,
    required this.createdAt,
    this.messageCount = 0,
  });
}

class NoteBoxEntity {
  final NoteEntity note;
  final PlaceEntity place;

  const NoteBoxEntity({required this.note, required this.place});
}
