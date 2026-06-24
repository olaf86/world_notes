typedef InRangeStateWriter =
    Future<void> Function({required String placeId, required bool inRange});

/// Serializes and de-duplicates in-range state writes.
///
/// A missing local state is intentionally treated as unknown rather than
/// outside. This makes the first position/geofence event after an app restart
/// refresh the server TTL, while repeated events in the same process are
/// ignored.
class InRangeStateSynchronizer {
  final InRangeStateWriter _writer;
  final Map<String, ({bool inRange, bool confirmed})> _states = {};

  Future<void> _queue = Future.value();
  int _generation = 0;

  InRangeStateSynchronizer(this._writer);

  Set<String> get inRangePlaceIds => {
    for (final entry in _states.entries)
      if (entry.value.inRange) entry.key,
  };

  Future<bool> setState({
    required String placeId,
    required bool inRange,
    bool assumeIfUnknown = false,
    bool confirmIfAssumed = false,
  }) {
    final previous = _queue;
    final operation = previous.then((_) async {
      final current = _states[placeId];
      if (current?.inRange == inRange &&
          (current!.confirmed || !confirmIfAssumed)) {
        return false;
      }
      if (!_states.containsKey(placeId) && assumeIfUnknown) {
        _states[placeId] = (inRange: inRange, confirmed: false);
        return false;
      }

      final generation = _generation;
      await _writer(placeId: placeId, inRange: inRange);
      if (_generation == generation) {
        _states[placeId] = (inRange: inRange, confirmed: true);
      }
      return true;
    });
    _queue = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  /// Drops process-local knowledge without writing to the server.
  ///
  /// Native geofences remain active while the app is backgrounded, so the next
  /// delivered transition must be allowed to refresh the server state.
  void forgetAll() {
    _generation += 1;
    _states.clear();
  }
}
