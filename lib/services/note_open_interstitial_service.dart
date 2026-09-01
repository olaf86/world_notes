import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// The UI-facing gate used immediately before opening a note from the map.
abstract interface class NoteOpenInterstitialGate {
  Future<void> beforeNoteOpen({required String placeId});
}

class DisabledNoteOpenInterstitialGate implements NoteOpenInterstitialGate {
  const DisabledNoteOpenInterstitialGate();

  @override
  Future<void> beforeNoteOpen({required String placeId}) async {}
}

/// Persisted per-user state for the current interval between interstitials.
@immutable
class NoteOpenInterstitialState {
  final Set<String> openedPlaceIds;
  final DateTime? lastShownAt;

  const NoteOpenInterstitialState({
    this.openedPlaceIds = const {},
    this.lastShownAt,
  });
}

abstract interface class NoteOpenInterstitialStateStore {
  Future<NoteOpenInterstitialState> read(String userId);

  Future<void> recordNoteOpen(String userId, Set<String> openedPlaceIds);

  Future<void> recordAdShown(String userId, DateTime shownAt);
}

class SharedPreferencesNoteOpenInterstitialStateStore
    implements NoteOpenInterstitialStateStore {
  static const _openedPlaceIdsPrefix = 'note_interstitial_opened_place_ids_';
  static const _lastShownAtPrefix = 'note_interstitial_last_shown_at_';

  @override
  Future<NoteOpenInterstitialState> read(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    final openedPlaceIds = preferences.getStringList(
      '$_openedPlaceIdsPrefix$userId',
    );
    final lastShownAtMilliseconds = preferences.getInt(
      '$_lastShownAtPrefix$userId',
    );
    return NoteOpenInterstitialState(
      openedPlaceIds: Set.unmodifiable(openedPlaceIds ?? const <String>[]),
      lastShownAt: lastShownAtMilliseconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              lastShownAtMilliseconds,
              isUtc: true,
            ),
    );
  }

  @override
  Future<void> recordNoteOpen(String userId, Set<String> openedPlaceIds) async {
    final preferences = await SharedPreferences.getInstance();
    final sortedPlaceIds = openedPlaceIds.toList()..sort();
    await preferences.setStringList(
      '$_openedPlaceIdsPrefix$userId',
      sortedPlaceIds,
    );
  }

  @override
  Future<void> recordAdShown(String userId, DateTime shownAt) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setStringList('$_openedPlaceIdsPrefix$userId', const []),
      preferences.setInt(
        '$_lastShownAtPrefix$userId',
        shownAt.toUtc().millisecondsSinceEpoch,
      ),
    ]);
  }
}

abstract interface class InterstitialAdClient {
  bool get isReady;

  Future<void> load();

  /// Completes when the ad has been dismissed (or failed to show), and
  /// returns whether full-screen content was actually presented.
  Future<bool> show();

  void dispose();
}

class GoogleInterstitialAdClient implements InterstitialAdClient {
  InterstitialAd? _ad;
  bool _isLoading = false;
  bool _isDisposed = false;

  @override
  bool get isReady => !_isDisposed && _ad != null;

  @override
  Future<void> load() async {
    if (_isDisposed || _isLoading || _ad != null) return;
    _isLoading = true;
    try {
      await InterstitialAd.load(
        adUnitId: AppConfig.interstitialAdUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _isLoading = false;
            if (_isDisposed) {
              unawaited(ad.dispose());
              return;
            }
            _ad = ad;
          },
          onAdFailedToLoad: (error) {
            _isLoading = false;
            debugPrint('[AdMob] Interstitial failed to load: $error');
          },
        ),
      );
    } catch (error) {
      _isLoading = false;
      debugPrint('[AdMob] Interstitial load request failed: $error');
    }
  }

  @override
  Future<bool> show() async {
    final ad = _ad;
    if (_isDisposed || ad == null) return false;
    _ad = null;

    final completion = Completer<bool>();
    var didShow = false;

    void complete(bool value) {
      if (!completion.isCompleted) completion.complete(value);
    }

    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdShowedFullScreenContent: (_) => didShow = true,
      onAdDismissedFullScreenContent: (ad) {
        unawaited(ad.dispose());
        complete(didShow);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('[AdMob] Interstitial failed to show: $error');
        unawaited(ad.dispose());
        complete(false);
      },
    );

    try {
      await ad.show();
    } catch (error) {
      debugPrint('[AdMob] Interstitial show request failed: $error');
      unawaited(ad.dispose());
      complete(false);
    }
    return completion.future;
  }

  @override
  void dispose() {
    _isDisposed = true;
    final ad = _ad;
    _ad = null;
    if (ad != null) unawaited(ad.dispose());
  }
}

/// Applies the per-user note-open policy and coordinates a preloaded ad.
///
/// Only distinct place IDs count within a cycle. There is deliberately no
/// maximum-open rule: after the minimum, every eligible open is an independent
/// probability roll, including the first open after an app restart.
class NoteOpenInterstitialController implements NoteOpenInterstitialGate {
  final String userId;
  final NoteOpenInterstitialStateStore stateStore;
  final InterstitialAdClient adClient;
  final int minimumNoteOpens;
  final double displayProbability;
  final Duration cooldown;
  final double Function() randomDouble;
  final DateTime Function() now;

  bool _isHandlingOpen = false;
  bool _isDisposed = false;

  NoteOpenInterstitialController({
    required this.userId,
    required this.stateStore,
    required this.adClient,
    this.minimumNoteOpens = AppConfig.interstitialMinimumNoteOpens,
    this.displayProbability = AppConfig.interstitialDisplayProbability,
    this.cooldown = AppConfig.interstitialCooldown,
    double Function()? randomDouble,
    DateTime Function()? now,
  }) : assert(minimumNoteOpens >= 0),
       assert(displayProbability >= 0 && displayProbability <= 1),
       randomDouble = randomDouble ?? Random().nextDouble,
       now = now ?? DateTime.now;

  void preload() {
    if (_isDisposed) return;
    unawaited(adClient.load());
  }

  @override
  Future<void> beforeNoteOpen({required String placeId}) async {
    final normalizedPlaceId = placeId.trim();
    if (_isDisposed || normalizedPlaceId.isEmpty || _isHandlingOpen) return;

    _isHandlingOpen = true;
    try {
      final state = await stateStore.read(userId);

      // Reopening the same note within one cycle does not advance the counter
      // and does not create another chance to show an ad.
      if (state.openedPlaceIds.contains(normalizedPlaceId)) return;

      final currentTime = now().toUtc();
      final cooldownElapsed =
          state.lastShownAt == null ||
          currentTime.difference(state.lastShownAt!.toUtc()) >= cooldown;
      final canAttemptToShow =
          state.openedPlaceIds.length >= minimumNoteOpens &&
          cooldownElapsed &&
          adClient.isReady;

      if (canAttemptToShow && randomDouble() < displayProbability) {
        final didShow = await adClient.show();
        if (didShow) {
          // Do not count the note that follows the ad. The next distinct note
          // must once again open without an interstitial.
          await stateStore.recordAdShown(userId, now().toUtc());
          return;
        }
      }

      await stateStore.recordNoteOpen(userId, {
        ...state.openedPlaceIds,
        normalizedPlaceId,
      });
    } catch (error, stack) {
      // Ads must never prevent access to a note.
      debugPrint('[AdMob] Note-open interstitial gate failed: $error\n$stack');
    } finally {
      _isHandlingOpen = false;
      preload();
    }
  }

  void dispose() {
    _isDisposed = true;
    adClient.dispose();
  }
}
