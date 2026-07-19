import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/services/note_open_interstitial_service.dart';

void main() {
  const userId = 'user-1';
  late _MemoryStateStore store;
  late _FakeInterstitialAdClient adClient;
  late DateTime currentTime;

  setUp(() {
    store = _MemoryStateStore();
    adClient = _FakeInterstitialAdClient(isReady: true);
    currentTime = DateTime.utc(2026, 7, 19, 12);
  });

  NoteOpenInterstitialController controller({double randomValue = 0}) {
    return NoteOpenInterstitialController(
      userId: userId,
      stateStore: store,
      adClient: adClient,
      randomDouble: () => randomValue,
      now: () => currentTime,
    );
  }

  test('first two distinct notes are ad-free and third can show', () async {
    final gate = controller();

    await gate.beforeNoteOpen(placeId: 'place-1');
    await gate.beforeNoteOpen(placeId: 'place-2');
    expect(adClient.showCount, 0);

    await gate.beforeNoteOpen(placeId: 'place-3');

    expect(adClient.showCount, 1);
    final state = await store.read(userId);
    expect(state.openedPlaceIds, isEmpty);
    expect(state.lastShownAt, currentTime);
  });

  test(
    'uses an independent 20 percent roll without a forced maximum',
    () async {
      final gate = controller(randomValue: 0.20);

      for (var index = 1; index <= 20; index += 1) {
        await gate.beforeNoteOpen(placeId: 'place-$index');
      }

      expect(adClient.showCount, 0);
      expect((await store.read(userId)).openedPlaceIds, hasLength(20));
    },
  );

  test('reopening a note neither advances the count nor rolls again', () async {
    final gate = controller();

    await gate.beforeNoteOpen(placeId: 'place-1');
    await gate.beforeNoteOpen(placeId: 'place-1');
    await gate.beforeNoteOpen(placeId: 'place-2');
    await gate.beforeNoteOpen(placeId: 'place-1');

    expect(adClient.showCount, 0);
    expect((await store.read(userId)).openedPlaceIds, {'place-1', 'place-2'});

    await gate.beforeNoteOpen(placeId: 'place-3');
    expect(adClient.showCount, 1);
  });

  test('cooldown blocks ads while note opens continue to count', () async {
    store.states[userId] = NoteOpenInterstitialState(
      openedPlaceIds: const {'place-1', 'place-2'},
      lastShownAt: currentTime.subtract(const Duration(minutes: 5)),
    );
    final gate = controller();

    await gate.beforeNoteOpen(placeId: 'place-3');
    expect(adClient.showCount, 0);

    currentTime = currentTime.add(const Duration(minutes: 20));
    await gate.beforeNoteOpen(placeId: 'place-4');
    expect(adClient.showCount, 1);
  });

  test('first note after an app restart is always ad-free', () async {
    store.states[userId] = const NoteOpenInterstitialState(
      openedPlaceIds: {'place-1', 'place-2'},
    );
    final gate = controller();

    await gate.beforeNoteOpen(placeId: 'place-3');
    expect(adClient.showCount, 0);

    await gate.beforeNoteOpen(placeId: 'place-4');
    expect(adClient.showCount, 1);
  });

  test('an unavailable ad never delays or resets the cycle', () async {
    adClient.isReady = false;
    final gate = controller();

    await gate.beforeNoteOpen(placeId: 'place-1');
    await gate.beforeNoteOpen(placeId: 'place-2');
    await gate.beforeNoteOpen(placeId: 'place-3');

    expect(adClient.showCount, 0);
    expect((await store.read(userId)).openedPlaceIds, hasLength(3));
  });

  test('a failed show does not reset the cycle', () async {
    adClient.showResult = false;
    final gate = controller();

    await gate.beforeNoteOpen(placeId: 'place-1');
    await gate.beforeNoteOpen(placeId: 'place-2');
    await gate.beforeNoteOpen(placeId: 'place-3');

    expect(adClient.showCount, 1);
    expect((await store.read(userId)).openedPlaceIds, hasLength(3));
  });
}

class _MemoryStateStore implements NoteOpenInterstitialStateStore {
  final Map<String, NoteOpenInterstitialState> states = {};

  @override
  Future<NoteOpenInterstitialState> read(String userId) async {
    return states[userId] ?? const NoteOpenInterstitialState();
  }

  @override
  Future<void> recordAdShown(String userId, DateTime shownAt) async {
    states[userId] = NoteOpenInterstitialState(lastShownAt: shownAt);
  }

  @override
  Future<void> recordNoteOpen(String userId, Set<String> openedPlaceIds) async {
    final previous = states[userId];
    states[userId] = NoteOpenInterstitialState(
      openedPlaceIds: Set.unmodifiable(openedPlaceIds),
      lastShownAt: previous?.lastShownAt,
    );
  }
}

class _FakeInterstitialAdClient implements InterstitialAdClient {
  @override
  bool isReady;
  bool showResult = true;
  int loadCount = 0;
  int showCount = 0;
  bool isDisposed = false;

  _FakeInterstitialAdClient({required this.isReady});

  @override
  void dispose() {
    isDisposed = true;
    isReady = false;
  }

  @override
  Future<void> load() async {
    loadCount += 1;
  }

  @override
  Future<bool> show() async {
    showCount += 1;
    isReady = false;
    return showResult;
  }
}
