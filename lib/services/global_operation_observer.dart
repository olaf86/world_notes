import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/world_catalog.dart';
import '../domain/entities/global_operation_entity.dart';
import '../domain/repositories/global_operation_repository.dart';

typedef GlobalOperationErrorReporter =
    Future<void> Function(Object error, StackTrace stack);

/// App-scoped observer for accepted operations that survive navigation/restart.
final class GlobalOperationObserver {
  GlobalOperationObserver({
    required String userId,
    required GlobalOperationRepository repository,
    required SharedPreferences preferences,
    required GlobalOperationErrorReporter reportError,
  }) : _storageKey = 'global_operations_v1:$userId',
       _repository = repository,
       _preferences = preferences,
       _reportError = reportError,
       _operations = StreamController<List<GlobalOperationEntity>>.broadcast();

  final String _storageKey;
  final GlobalOperationRepository _repository;
  final SharedPreferences _preferences;
  final GlobalOperationErrorReporter _reportError;
  final StreamController<List<GlobalOperationEntity>> _operations;
  final Set<GlobalOperationReference> _remembered = {};
  final Map<GlobalOperationReference, GlobalOperationEntity> _latest = {};
  final Map<GlobalOperationReference, StreamSubscription<GlobalOperationEntity>>
  _subscriptions = {};
  Future<void>? _starting;
  bool _disposed = false;

  Stream<List<GlobalOperationEntity>> get operations => _operations.stream;

  Future<void> start() => _starting ??= _restore();

  /// Validates an accepted callable result and remembers it only while pending.
  Future<GlobalOperationReference> trackAcceptedResponse(
    Map<String, dynamic> response,
  ) async {
    final authorityWorld = response['authorityWorld'];
    final operationId = response['operationId'];
    if (authorityWorld is! String || operationId is! String) {
      throw const FormatException('Global operation response is invalid.');
    }
    final reference = GlobalOperationReference(
      authorityWorld: WorldId(authorityWorld),
      operationId: operationId,
    );
    final status = GlobalOperationStatus.parse(response['status']);
    if (status == GlobalOperationStatus.pending) await track(reference);
    return reference;
  }

  Future<void> track(GlobalOperationReference reference) async {
    await start();
    if (_disposed || !_remembered.add(reference)) return;
    await _persist();
    _listen(reference);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait(
      _subscriptions.values.map((subscription) => subscription.cancel()),
    );
    _subscriptions.clear();
    await _operations.close();
  }

  Future<void> _restore() async {
    final encoded = _preferences.getString(_storageKey);
    if (encoded == null) return;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) throw const FormatException('Expected a list.');
      for (final item in decoded) {
        if (item is! Map) throw const FormatException('Expected an object.');
        final authorityWorld = item['authorityWorld'];
        final operationId = item['operationId'];
        if (authorityWorld is! String || operationId is! String) {
          throw const FormatException('Stored operation fields are invalid.');
        }
        _remembered.add(
          GlobalOperationReference(
            authorityWorld: WorldId(authorityWorld),
            operationId: operationId,
          ),
        );
      }
    } catch (error, stack) {
      await _reportError(error, stack);
      _remembered.clear();
      await _preferences.remove(_storageKey);
      return;
    }
    for (final reference in _remembered) {
      _listen(reference);
    }
  }

  void _listen(GlobalOperationReference reference) {
    if (_disposed || _subscriptions.containsKey(reference)) return;
    _subscriptions[reference] = _repository
        .watchOperation(reference)
        .listen(
          (operation) {
            _latest[reference] = operation;
            _emit();
            if (operation.isTerminal) unawaited(_forget(reference));
          },
          onError: (Object error, StackTrace stack) {
            unawaited(_reportError(error, stack));
          },
        );
  }

  Future<void> _forget(GlobalOperationReference reference) async {
    if (!_remembered.remove(reference)) return;
    await _persist();
    await _subscriptions.remove(reference)?.cancel();
  }

  Future<void> _persist() async {
    final values =
        _remembered
            .map(
              (reference) => {
                'authorityWorld': reference.authorityWorld.value,
                'operationId': reference.operationId,
              },
            )
            .toList()
          ..sort((a, b) {
            final world = (a['authorityWorld']!).compareTo(
              b['authorityWorld']!,
            );
            return world != 0
                ? world
                : (a['operationId']!).compareTo(b['operationId']!);
          });
    if (values.isEmpty) {
      await _preferences.remove(_storageKey);
    } else {
      await _preferences.setString(_storageKey, jsonEncode(values));
    }
  }

  void _emit() {
    if (_disposed) return;
    final snapshot = _latest.values.toList()
      ..sort((a, b) => b.acceptedAt.compareTo(a.acceptedAt));
    _operations.add(List.unmodifiable(snapshot));
  }
}
