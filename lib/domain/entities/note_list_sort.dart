/// The ordering options shared by note-list screens.
enum NoteListSort { distance, newest, expiresSoonest, mostLiked }

/// Orders note-like values with consistent tie breakers.
///
/// [distance] is optional so lists that have not acquired a current location
/// can still use the distance option without failing. Those items fall back to
/// newest-first order until a location is available.
List<T> sortNoteList<T>(
  Iterable<T> items, {
  required NoteListSort sort,
  required DateTime Function(T item) createdAt,
  required DateTime Function(T item) expiresAt,
  required int Function(T item) likeCount,
  required String Function(T item) id,
  double Function(T item)? distance,
}) {
  final sorted = items.toList();
  sorted.sort((a, b) {
    final primary = switch (sort) {
      NoteListSort.distance => _compareNullableDistance(
        distance?.call(a),
        distance?.call(b),
      ),
      NoteListSort.newest => createdAt(b).compareTo(createdAt(a)),
      NoteListSort.expiresSoonest => expiresAt(a).compareTo(expiresAt(b)),
      NoteListSort.mostLiked => likeCount(b).compareTo(likeCount(a)),
    };
    if (primary != 0) return primary;

    final byCreatedAt = createdAt(b).compareTo(createdAt(a));
    if (byCreatedAt != 0) return byCreatedAt;
    return id(a).compareTo(id(b));
  });
  return sorted;
}

int _compareNullableDistance(double? a, double? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}
