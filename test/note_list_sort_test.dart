import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/domain/entities/note_list_sort.dart';

void main() {
  final now = DateTime.utc(2026, 7, 13, 12);
  final items = [
    _Note(
      id: 'far',
      createdAt: now.subtract(const Duration(days: 1)),
      expiresAt: now.add(const Duration(days: 3)),
      likes: 2,
      distance: 400,
      lastActivityAt: now.subtract(const Duration(hours: 1)),
      archivedAt: now.subtract(const Duration(days: 1)),
    ),
    _Note(
      id: 'popular',
      createdAt: now.subtract(const Duration(days: 3)),
      expiresAt: now.add(const Duration(days: 1)),
      likes: 8,
      distance: 200,
      lastActivityAt: now.subtract(const Duration(days: 2)),
      archivedAt: now.subtract(const Duration(days: 3)),
    ),
    _Note(
      id: 'new',
      createdAt: now,
      expiresAt: now.add(const Duration(days: 7)),
      likes: 1,
      distance: 50,
      lastActivityAt: now.subtract(const Duration(days: 4)),
      archivedAt: now,
    ),
  ];

  List<String> ids(NoteListSort sort, {bool withDistance = true}) {
    final double Function(_Note item)? distance = withDistance
        ? (item) => item.distance
        : null;
    return sortNoteList(
      items,
      sort: sort,
      createdAt: (item) => item.createdAt,
      lastActivityAt: (item) => item.lastActivityAt,
      archivedAt: (item) => item.archivedAt,
      expiresAt: (item) => item.expiresAt,
      likeCount: (item) => item.likes,
      id: (item) => item.id,
      distance: distance,
    ).map((item) => item.id).toList();
  }

  test('orders notes by each requested criterion', () {
    expect(ids(NoteListSort.distance), ['new', 'popular', 'far']);
    expect(ids(NoteListSort.newest), ['new', 'far', 'popular']);
    expect(ids(NoteListSort.lastActivity), ['far', 'popular', 'new']);
    expect(ids(NoteListSort.expiresSoonest), ['popular', 'far', 'new']);
    expect(ids(NoteListSort.mostLiked), ['popular', 'far', 'new']);
    expect(ids(NoteListSort.archivedNewest), ['new', 'far', 'popular']);
    expect(ids(NoteListSort.archivedOldest), ['popular', 'far', 'new']);
  });

  test('distance order falls back to newest when location is unavailable', () {
    expect(ids(NoteListSort.distance, withDistance: false), [
      'new',
      'far',
      'popular',
    ]);
  });
}

class _Note {
  final String id;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int likes;
  final double distance;
  final DateTime lastActivityAt;
  final DateTime archivedAt;

  const _Note({
    required this.id,
    required this.createdAt,
    required this.expiresAt,
    required this.likes,
    required this.distance,
    required this.lastActivityAt,
    required this.archivedAt,
  });
}
