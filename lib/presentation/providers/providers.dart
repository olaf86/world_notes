import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_config.dart';
import '../../config/bootstrap_world_catalog.dart';
import '../../config/runtime_mode.dart';
import '../../config/world_catalog.dart';
import '../../config/world_navigation.dart';
import '../../core/map_style.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../data/repositories/follow_repository_impl.dart';
import '../../data/repositories/message_repository_impl.dart';
import '../../data/repositories/notice_repository_impl.dart';
import '../../data/repositories/place_repository_impl.dart';
import '../../data/repositories/user_block_repository_impl.dart';
import '../../domain/entities/follow_entity.dart';
import '../../domain/entities/admin_moderation_review_entity.dart';
import '../../domain/entities/message_thread_item.dart';
import '../../domain/entities/note_visitor_entity.dart';
import '../../domain/entities/notice_entity.dart';
import '../../domain/entities/note_list_sort.dart';
import '../../domain/entities/pin_summary_entity.dart';
import '../../domain/entities/place_entity.dart';
import '../../domain/entities/public_profile_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/entities/user_block_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/follow_repository.dart';
import '../../domain/repositories/message_repository.dart';
import '../../domain/repositories/notice_repository.dart';
import '../../domain/repositories/place_repository.dart';
import '../../domain/repositories/user_block_repository.dart';
import '../../l10n/app_locale.dart';
import '../../services/ad_privacy_service.dart';
import '../../services/location_service.dart';
import '../../services/admin_moderation_service.dart';
import '../../services/message_image_service.dart';
import '../../services/my_notes_notification_service.dart';
import '../../services/notice_notification_service.dart';
import '../../services/note_open_interstitial_service.dart';
import '../../services/subscription_service.dart';
import '../../services/world_firebase_clients.dart';

// --- Infrastructure ---

final worldCatalogProvider = Provider<WorldCatalog>(
  (_) => bootstrapWorldCatalog,
);

/// Permanent home for pre-multi-world accounts during the P04 rollout.
final homeWorldProvider = Provider<WorldId>((_) => asiaWorldId);

class SelectedWorldNotifier extends Notifier<WorldId> {
  @override
  WorldId build() {
    final homeWorld = ref.watch(homeWorldProvider);
    ref.watch(worldCatalogProvider).requireContentWorld(homeWorld);
    return homeWorld;
  }

  void selectWorld(WorldId worldId) {
    ref.read(worldCatalogProvider).requireContentWorld(worldId);
    state = worldId;
  }
}

final selectedWorldProvider = NotifierProvider<SelectedWorldNotifier, WorldId>(
  SelectedWorldNotifier.new,
);

/// Canonical route builder with the current content world already injected.
final selectedWorldNavigationProvider = Provider<WorldNavigation>((ref) {
  return WorldNavigation(ref.watch(selectedWorldProvider));
});

final worldSelectionProvider = Provider<WorldSelection>((ref) {
  return WorldSelection(
    homeWorld: ref.watch(homeWorldProvider),
    selectedWorld: ref.watch(selectedWorldProvider),
  );
});

final selectedWorldCatalogEntryProvider = Provider<WorldCatalogEntry>((ref) {
  return ref
      .watch(worldCatalogProvider)
      .requireContentWorld(ref.watch(selectedWorldProvider));
});

final worldFirebaseClientCacheProvider = Provider<WorldFirebaseClientCache>((
  _,
) {
  return WorldFirebaseClientCache(
    app: Firebase.app(),
    emulatorHost: shouldUseFirebaseEmulators ? firebaseEmulatorHost() : null,
  );
});

final worldFirebaseClientsProvider =
    Provider.family<WorldFirebaseClients, WorldId>((ref, worldId) {
      final world = ref
          .watch(worldCatalogProvider)
          .requireContentWorld(worldId);
      return ref.watch(worldFirebaseClientCacheProvider).forWorld(world);
    });

final selectedWorldClientsProvider = Provider<WorldFirebaseClients>((ref) {
  return ref.watch(
    worldFirebaseClientsProvider(ref.watch(selectedWorldProvider)),
  );
});

final selectedWorldFirestoreProvider = Provider<FirebaseFirestore>((ref) {
  return ref.watch(selectedWorldClientsProvider).firestore;
});

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (_) => FirebaseAuth.instance,
);

final selectedWorldStorageProvider = Provider<FirebaseStorage>((ref) {
  return ref.watch(selectedWorldClientsProvider).storage;
});

final firebaseMessagingProvider = Provider<FirebaseMessaging>(
  (_) => FirebaseMessaging.instance,
);

final firebaseCrashlyticsProvider = Provider<FirebaseCrashlytics>(
  (_) => FirebaseCrashlytics.instance,
);

/// Preloaded before [runApp] in production so persisted UI preferences are
/// available on the first rendered frame. Tests may leave this null and get
/// the system-language default.
final sharedPreferencesProvider = Provider<SharedPreferences?>((_) => null);

final selectedWorldFunctionsProvider = Provider<WorldFunctionsClient>((ref) {
  return ref.watch(selectedWorldClientsProvider).functions;
});

// --- Services ---

final locationServiceProvider = Provider<LocationService>(
  (_) => LocationService(),
);

final subscriptionServiceProvider = Provider<SubscriptionService>(
  (_) => SubscriptionService(),
);

final adPrivacyServiceProvider = Provider<AdPrivacyService>(
  (_) => GoogleAdPrivacyService(),
);

/// Starts UMP only after authentication and the subscription state have
/// resolved. UMP decides whether a form is needed on this app launch and, on
/// iOS, sequences a published IDFA explanation before the one-time ATT alert.
final adPrivacyStatusProvider = FutureProvider<AdPrivacyStatus>((ref) async {
  if (!AppConfig.supportsMobileAds || !AppConfig.hasRequiredAdUnitIds) {
    return AdPrivacyStatus.disabled;
  }

  final user = ref.watch(authStateProvider).valueOrNull;
  final isPremium = ref.watch(isPremiumProvider).valueOrNull;
  if (user == null || isPremium != false) {
    return AdPrivacyStatus.disabled;
  }

  return ref.watch(adPrivacyServiceProvider).gatherConsentAndInitialize();
});

final canRequestAdsProvider = Provider<bool>((ref) {
  return ref.watch(adPrivacyStatusProvider).valueOrNull?.canRequestAds ?? false;
});

final messageImageServiceProvider = Provider<MessageImageService>((ref) {
  final service = MessageImageService(
    storage: ref.watch(selectedWorldStorageProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Preloaded interstitial gate used only by the map note-opening flows.
/// Premium must resolve explicitly to false before the ad client is created.
final noteOpenInterstitialGateProvider = Provider<NoteOpenInterstitialGate>((
  ref,
) {
  if (!AppConfig.supportsMobileAds || !ref.watch(canRequestAdsProvider)) {
    return const DisabledNoteOpenInterstitialGate();
  }

  final user = ref.watch(authStateProvider).valueOrNull;
  final isPremium = ref.watch(isPremiumProvider).valueOrNull;
  if (user == null || isPremium != false) {
    return const DisabledNoteOpenInterstitialGate();
  }

  final controller = NoteOpenInterstitialController(
    userId: user.id,
    stateStore: SharedPreferencesNoteOpenInterstitialStateStore(),
    adClient: GoogleInterstitialAdClient(),
  );
  controller.preload();
  ref.onDispose(controller.dispose);
  return controller;
});

final messageImageUrlProvider = FutureProvider.autoDispose
    .family<String, String>((ref, storagePath) {
      return ref.watch(messageImageServiceProvider).downloadUrl(storagePath);
    });

final myNotesNotificationServiceProvider = Provider<MyNotesNotificationService>(
  (ref) {
    final service = MyNotesNotificationService(
      messaging: ref.watch(firebaseMessagingProvider),
      functions: ref.watch(selectedWorldFunctionsProvider),
      auth: ref.watch(firebaseAuthProvider),
      crashlytics: ref.watch(firebaseCrashlyticsProvider),
    );
    if (!screenshotMode) {
      service.startRegistrationSync();
    }
    ref.onDispose(service.dispose);
    return service;
  },
);

final noticeNotificationServiceProvider = Provider<NoticeNotificationService>((
  ref,
) {
  final service = NoticeNotificationService(
    messaging: ref.watch(firebaseMessagingProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final adminModerationServiceProvider = Provider<AdminModerationService>((ref) {
  return AdminModerationService(
    functions: ref.watch(selectedWorldFunctionsProvider),
  );
});

// --- App language ---

final appLanguagePreferenceProvider =
    StateNotifierProvider<AppLanguagePreferenceNotifier, AppLanguagePreference>(
      (ref) {
        return AppLanguagePreferenceNotifier(
          auth: ref.watch(firebaseAuthProvider),
          firestore: ref.watch(selectedWorldFirestoreProvider),
          functions: ref.watch(selectedWorldFunctionsProvider),
          preferences: ref.watch(sharedPreferencesProvider),
          syncAccount: !screenshotMode,
        );
      },
    );

/// Keeps the signed-in account preference authoritative while mirroring it to
/// local storage for a flicker-free and offline-capable next launch.
class AppLanguagePreferenceNotifier
    extends StateNotifier<AppLanguagePreference> {
  AppLanguagePreferenceNotifier({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required WorldFunctionsClient functions,
    required SharedPreferences? preferences,
    required bool syncAccount,
  }) : _auth = auth,
       _firestore = firestore,
       _functions = functions,
       _preferences = preferences,
       super(
         AppLanguagePreference.fromLocalStorage(
           preferences?.getString(appLanguagePreferenceKey),
         ),
       ) {
    if (syncAccount) {
      _authSubscription = auth.authStateChanges().listen(_onAuthChanged);
    }
  }

  AppLanguagePreferenceNotifier.localOnly({
    required SharedPreferences preferences,
  }) : _auth = null,
       _firestore = null,
       _functions = null,
       _preferences = preferences,
       super(
         AppLanguagePreference.fromLocalStorage(
           preferences.getString(appLanguagePreferenceKey),
         ),
       );

  final FirebaseAuth? _auth;
  final FirebaseFirestore? _firestore;
  final WorldFunctionsClient? _functions;
  SharedPreferences? _preferences;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _accountSubscription;
  String? _accountBeingSeeded;
  AppLanguagePreference? _pendingPreference;

  Future<void> setPreference(AppLanguagePreference preference) async {
    state = preference;
    await _persistLocally(preference);

    final functions = _functions;
    if (_auth?.currentUser == null || functions == null) return;
    _pendingPreference = preference;
    try {
      await functions.httpsCallable('setLanguagePreference').call<void>({
        'languagePreference': preference.storageValue,
      });
    } catch (_) {
      _pendingPreference = null;
      rethrow;
    }
  }

  void _onAuthChanged(User? user) {
    _accountSubscription?.cancel();
    _accountSubscription = null;
    _accountBeingSeeded = null;
    _pendingPreference = null;

    if (user == null) {
      _applyAccountPreference(AppLanguagePreference.system);
      return;
    }

    final firestore = _firestore;
    if (firestore == null) return;
    _accountSubscription = firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen(
          (snapshot) => _onAccountSnapshot(user.uid, snapshot),
          onError: (Object error, StackTrace stack) {
            debugPrint(
              'Failed to sync account language preference: $error\n$stack',
            );
          },
        );
  }

  void _onAccountSnapshot(
    String userId,
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (!snapshot.exists) return;
    final rawPreference = snapshot.data()?['languagePreference'];
    final saved = AppLanguagePreference.tryParse(
      rawPreference is String ? rawPreference : null,
    );
    if (saved != null) {
      if (_pendingPreference != null && saved != _pendingPreference) return;
      _pendingPreference = null;
      _accountBeingSeeded = null;
      _applyAccountPreference(saved);
      return;
    }

    // Existing accounts predate this field. Preserve the app's historical
    // behavior by starting those accounts on the system-language setting.
    if (_accountBeingSeeded == userId) return;
    _accountBeingSeeded = userId;
    _applyAccountPreference(AppLanguagePreference.system);
    unawaited(_seedAccountPreference());
  }

  Future<void> _seedAccountPreference() async {
    final functions = _functions;
    if (functions == null) return;
    try {
      await functions.httpsCallable('setLanguagePreference').call<void>({
        'languagePreference': AppLanguagePreference.system.storageValue,
      });
    } catch (error, stack) {
      _accountBeingSeeded = null;
      debugPrint(
        'Failed to initialize account language preference: $error\n$stack',
      );
    }
  }

  void _applyAccountPreference(AppLanguagePreference preference) {
    state = preference;
    unawaited(_persistLocally(preference));
  }

  Future<void> _persistLocally(AppLanguagePreference preference) async {
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    await preferences.setString(
      appLanguagePreferenceKey,
      preference.storageValue,
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _accountSubscription?.cancel();
    super.dispose();
  }
}

// --- Repositories ---

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(
    auth: ref.watch(firebaseAuthProvider),
    googleSignIn: GoogleSignIn(),
    firestore: ref.watch(selectedWorldFirestoreProvider),
    functions: ref.watch(selectedWorldFunctionsProvider),
    myNotesNotificationService: ref.watch(myNotesNotificationServiceProvider),
    subscriptionService: ref.watch(subscriptionServiceProvider),
    messageImageService: ref.watch(messageImageServiceProvider),
  );
});

final placeRepositoryProvider = Provider<PlaceRepository>((ref) {
  return PlaceRepositoryImpl(
    firestore: ref.watch(selectedWorldFirestoreProvider),
    functions: ref.watch(selectedWorldFunctionsProvider),
    storage: ref.watch(selectedWorldStorageProvider),
  );
});

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepositoryImpl(
    firestore: ref.watch(selectedWorldFirestoreProvider),
    functions: ref.watch(selectedWorldFunctionsProvider),
    storage: ref.watch(selectedWorldStorageProvider),
  );
});

final followRepositoryProvider = Provider<FollowRepository>((ref) {
  return FollowRepositoryImpl(
    firestore: ref.watch(selectedWorldFirestoreProvider),
    functions: ref.watch(selectedWorldFunctionsProvider),
  );
});

final noticeRepositoryProvider = Provider<NoticeRepository>((ref) {
  return NoticeRepositoryImpl(
    firestore: ref.watch(selectedWorldFirestoreProvider),
  );
});

final userBlockRepositoryProvider = Provider<UserBlockRepository>((ref) {
  return UserBlockRepositoryImpl(
    firestore: ref.watch(selectedWorldFirestoreProvider),
    functions: ref.watch(selectedWorldFunctionsProvider),
  );
});

/// Waits for the private block list before subscribing to user-derived
/// content. The loading stream intentionally emits no value, so callers stay
/// loading instead of briefly rendering unfiltered content. Riverpod rebuilds
/// the caller when [blockedUserIdsProvider] resolves; failures remain visible
/// as provider errors rather than being mistaken for loading.
Stream<T> _afterBlockedUserIdsLoad<T>(
  AsyncValue<Set<String>> blockedUserIds,
  Stream<T> Function(Set<String> ids) createStream,
) {
  return blockedUserIds.when(
    data: createStream,
    loading: () => const Stream.empty(),
    error: Stream.error,
  );
}

// --- Auth state ---

final authStateProvider = StreamProvider<UserEntity?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

final userProfileProvider = StreamProvider.autoDispose
    .family<UserEntity?, String>((ref, userId) {
      final id = userId.trim();
      if (id.isEmpty) return Stream.value(null);
      return ref
          .watch(selectedWorldFirestoreProvider)
          .collection('users')
          .doc(id)
          .snapshots()
          .map((snap) {
            final data = snap.data();
            if (data == null) return null;
            final displayName = (data['displayName'] as String?)?.trim();
            return UserEntity(
              id: snap.id,
              name: displayName == null || displayName.isEmpty
                  ? 'User'
                  : displayName,
              email: data['email'] as String?,
              photoUrl: data['photoUrl'] as String?,
              isPremium: data['isPremium'] as bool? ?? false,
            );
          });
    });

final noteCreatorProfileProvider = Provider.autoDispose
    .family<UserEntity?, String>((ref, userId) {
      final id = userId.trim();
      if (id.isEmpty) return null;
      final profile = ref.watch(userProfileProvider(id)).valueOrNull;
      final currentUser = ref.watch(authStateProvider).valueOrNull;
      if (profile != null) return profile;
      return currentUser?.id == id ? currentUser : null;
    });

final adminClaimProvider = FutureProvider<bool>((ref) async {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) return false;
  final token = await ref
      .watch(firebaseAuthProvider)
      .currentUser
      ?.getIdTokenResult();
  return token?.claims?['admin'] == true;
});

// --- Social profiles and follows ---

final blockedUserIdsProvider = StreamProvider<Set<String>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const {});
  return ref.watch(userBlockRepositoryProvider).watchBlockedUserIds(user.id);
});

final blockedUsersProvider = StreamProvider<List<UserBlock>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.watch(userBlockRepositoryProvider).watchBlockedUsers(user.id);
});

final isUserBlockedProvider = StreamProvider.family<bool, String>((
  ref,
  blockedUserId,
) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.id == blockedUserId) return Stream.value(false);
  return ref
      .watch(userBlockRepositoryProvider)
      .watchIsBlocked(blockerUserId: user.id, blockedUserId: blockedUserId);
});

final publicProfileProvider = StreamProvider.family<PublicProfile?, String>((
  ref,
  userId,
) {
  return ref.watch(followRepositoryProvider).watchPublicProfile(userId);
});

final isFollowingUserProvider = StreamProvider.family<bool, String>((
  ref,
  followeeUid,
) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.id == followeeUid) return Stream.value(false);
  return ref
      .watch(followRepositoryProvider)
      .watchIsFollowing(followerUid: user.id, followeeUid: followeeUid);
});

class FollowListRequest {
  final String userId;
  final bool followers;

  const FollowListRequest({required this.userId, required this.followers});

  @override
  bool operator ==(Object other) =>
      other is FollowListRequest &&
      other.userId == userId &&
      other.followers == followers;

  @override
  int get hashCode => Object.hash(userId, followers);
}

final followFirstPageProvider =
    FutureProvider.family<FollowPage, FollowListRequest>((ref, request) async {
      final repository = ref.watch(followRepositoryProvider);
      final blockedUserIds = await ref.watch(blockedUserIdsProvider.future);
      return request.followers
          ? repository.listFollowers(
              userId: request.userId,
              excludedUserIds: blockedUserIds,
            )
          : repository.listFollowing(
              userId: request.userId,
              excludedUserIds: blockedUserIds,
            );
    });

// --- Notifications ---

final myNotesNotificationEnabledProvider = StreamProvider<bool>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(false);
  return ref
      .watch(selectedWorldFirestoreProvider)
      .collection('users')
      .doc(user.id)
      .collection('notificationSettings')
      .doc('main')
      .snapshots()
      .map((snap) => snap.data()?['myNotesEnabled'] == true);
});

final myNotesNotificationPreviewEnabledProvider = StreamProvider<bool>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(true);
  return ref
      .watch(selectedWorldFirestoreProvider)
      .collection('users')
      .doc(user.id)
      .collection('notificationSettings')
      .doc('main')
      .snapshots()
      .map((snap) => snap.data()?['myNotesPreviewEnabled'] != false);
});

final noticesProvider = StreamProvider<List<NoticeEntity>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return _afterBlockedUserIdsLoad(
    ref.watch(blockedUserIdsProvider),
    (blockedUserIds) => ref
        .watch(noticeRepositoryProvider)
        .watchNotices(user.id)
        .map(
          (notices) => notices
              .where((notice) => !blockedUserIds.contains(notice.sourceId))
              .toList(),
        ),
  );
});

final unreadNoticeCountProvider = Provider<int>((ref) {
  final notices = ref.watch(noticesProvider).valueOrNull ?? const [];
  return notices.where((notice) => notice.isUnread).length;
});

// --- Location ---

/// Live position stream. [ref.keepAlive] prevents the stream from being torn
/// down when the user switches tabs in the [ShellRoute] — without it, every
/// tab switch would restart GPS acquisition and briefly show
/// "location unavailable".
final positionStreamProvider = StreamProvider<Position>((ref) {
  ref.keepAlive();
  return ref.watch(locationServiceProvider).watchPosition();
});

/// Anchor position used as the centre of the map's notes-query window.
/// Updated from [positionStreamProvider] but only when the user has moved
/// further than the reload threshold, so the Firestore subscription isn't
/// thrashed by every minor GPS jitter. Lives in Riverpod (not MapScreen
/// state) so it survives any future widget-lifecycle reshuffling and so
/// other screens can read the same anchor.
class AnchorPositionNotifier extends Notifier<Position?> {
  static const double _reloadThresholdMetres = 200;

  @override
  Position? build() {
    ref.listen<AsyncValue<Position>>(positionStreamProvider, (_, next) {
      next.whenData(_consider);
    });
    // ref.listen doesn't fire for the value already cached by the stream
    // (common when this notifier is first activated after the stream has
    // been kept alive elsewhere). Seed from the current snapshot.
    return ref.read(positionStreamProvider).valueOrNull;
  }

  void _consider(Position pos) {
    final prev = state;
    if (prev == null) {
      state = pos;
      return;
    }
    final dist = Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      pos.latitude,
      pos.longitude,
    );
    if (dist >= _reloadThresholdMetres) {
      state = pos;
    }
  }
}

final anchorPositionProvider =
    NotifierProvider<AnchorPositionNotifier, Position?>(
      AnchorPositionNotifier.new,
    );

/// Whether the map is following the user's live GPS position.
final isTrackingProvider = StateProvider<bool>((ref) => false);

/// Whether the map shows the note-detail access radius around the live GPS
/// position. Kept outside the widget so switching between Map/List does not
/// unexpectedly reset the user's choice.
final isNoteAccessAreaVisibleProvider = StateProvider<bool>((ref) => false);

/// Centre coordinate used by the exploration layer. Unlike
/// [anchorPositionProvider], this follows the map camera when the user pans
/// away from their current location.
final mapSearchCenterProvider = StateProvider<MapLatLng?>((ref) => null);

/// Radius (in km) used by the current map-pins query. Kept separately from
/// [mapSearchCenterProvider] so list and manual refresh reuse the last map
/// viewport instead of snapping back to the default zoom's range.
final mapSearchRadiusKmProvider = StateProvider<double>(
  (ref) => MapPinSearchRadius.forZoom(AppConfig.defaultZoom),
);

// --- Map notes ---

class MapPinsRequest {
  final MapLatLng center;
  final MapLatLng user;
  final double radiusKm;

  const MapPinsRequest({
    required this.center,
    required this.user,
    required this.radiusKm,
  });

  @override
  bool operator ==(Object other) =>
      other is MapPinsRequest &&
      other.center == center &&
      other.user == user &&
      other.radiusKm == radiusKm;

  @override
  int get hashCode => Object.hash(center, user, radiusKm);
}

final mapPinsProvider = FutureProvider.family<List<PinSummary>, MapPinsRequest>(
  (ref, request) async {
    final user = await ref.watch(authStateProvider.future);
    if (user == null) return const <PinSummary>[];

    return ref
        .watch(placeRepositoryProvider)
        .listMapPins(
          centerLatitude: request.center.lat,
          centerLongitude: request.center.lng,
          userLatitude: request.user.lat,
          userLongitude: request.user.lng,
          searchRadiusKm: request.radiusKm,
        );
  },
);

/// Selected ordering for the list reached from the map.
final mapNotesSortProvider = StateProvider<NoteListSort>(
  (_) => NoteListSort.distance,
);

/// Live stream of a single place by id (null if it doesn't exist).
final placeProvider = StreamProvider.family<PlaceEntity?, String>((
  ref,
  placeId,
) {
  return ref.watch(placeRepositoryProvider).watchPlace(placeId);
});

/// A proximity check performed after the note route is already visible.
/// Keeping this in Riverpod deduplicates retries for the same route arguments
/// and lets the destination own its loading and error states.
class NoteAccessValidationRequest {
  final String placeId;
  final double latitude;
  final double longitude;

  const NoteAccessValidationRequest({
    required this.placeId,
    required this.latitude,
    required this.longitude,
  });

  @override
  bool operator ==(Object other) =>
      other is NoteAccessValidationRequest &&
      other.placeId == placeId &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(placeId, latitude, longitude);
}

final noteAccessValidationProvider = FutureProvider.autoDispose
    .family<void, NoteAccessValidationRequest>((ref, request) async {
      try {
        await ref
            .watch(placeRepositoryProvider)
            .validateNoteAccess(
              placeId: request.placeId,
              latitude: request.latitude,
              longitude: request.longitude,
            );
      } catch (error, stack) {
        try {
          await ref
              .read(firebaseCrashlyticsProvider)
              .recordError(
                error,
                stack,
                reason: 'Note destination access validation failed',
                fatal: false,
              );
        } catch (_) {
          // Access errors still belong in the destination UI even when
          // Crashlytics itself is unavailable.
        }
        rethrow;
      }
    });

/// The current user's access grant for a (private) note — null if none.
/// For public notes this isn't needed; callers gate on PlaceEntity.isPublic.
final noteMembershipProvider = StreamProvider.family<NoteMembership?, String>((
  ref,
  placeId,
) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(null);
  return ref
      .watch(placeRepositoryProvider)
      .watchMembership(placeId: placeId, userId: user.id);
});

/// Current user's like state for a note. The note screen only watches this
/// after content access has been granted, so private-note rules stay aligned
/// with the message stream behavior.
final noteLikeProvider = StreamProvider.family<bool, String>((ref, placeId) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(false);
  return ref
      .watch(placeRepositoryProvider)
      .watchNoteLike(placeId: placeId, userId: user.id);
});

/// Maintainer view of a private note's access list.
final noteMembersProvider = StreamProvider.family<List<NoteMember>, String>((
  ref,
  placeId,
) {
  return ref.watch(placeRepositoryProvider).watchMembers(placeId);
});

final recentNoteVisitorsProvider =
    StreamProvider.family<List<NoteVisitor>, String>((ref, placeId) {
      return _afterBlockedUserIdsLoad(
        ref.watch(blockedUserIdsProvider),
        (blockedUserIds) => ref
            .watch(placeRepositoryProvider)
            .watchRecentVisitors(
              placeId: placeId,
              limit: AppConfig.visitorPreviewExpandedMax,
            )
            .map(
              (visitors) => visitors
                  .where((visitor) => !blockedUserIds.contains(visitor.userId))
                  .toList(),
            ),
      );
    });

class NoteVisitorsRequest {
  final String placeId;
  final NoteVisitorSort sort;

  const NoteVisitorsRequest({required this.placeId, required this.sort});

  @override
  bool operator ==(Object other) =>
      other is NoteVisitorsRequest &&
      other.placeId == placeId &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(placeId, sort);
}

final noteVisitorsProvider =
    StreamProvider.family<List<NoteVisitor>, NoteVisitorsRequest>((
      ref,
      request,
    ) {
      return _afterBlockedUserIdsLoad(
        ref.watch(blockedUserIdsProvider),
        (blockedUserIds) => ref
            .watch(placeRepositoryProvider)
            .watchVisitors(placeId: request.placeId, sort: request.sort)
            .map(
              (visitors) => visitors
                  .where((visitor) => !blockedUserIds.contains(visitor.userId))
                  .toList(),
            ),
      );
    });

/// Active notes owned by the current user. Used by the My Notes read-only
/// destination; returns an empty stream while signed out.
final myPlacesProvider = StreamProvider<List<PlaceEntity>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.watch(placeRepositoryProvider).watchMyPlaces(user.id);
});

/// Server-backed note-cap precheck used by the creation destination. The form
/// can render while this runs; createNote remains the authoritative check.
final activeMyPlacesCountProvider = FutureProvider.autoDispose<int?>((
  ref,
) async {
  final repository = ref.watch(placeRepositoryProvider);
  final user = await ref.watch(authStateProvider.future);
  if (user == null) return null;
  return repository.countUserActivePlaces(user.id);
});

/// Total archived notes owned by the current user. The archived list itself is
/// fetched in pages.
final archivedMyPlacesCountProvider = FutureProvider<int?>((ref) {
  final authState = ref.watch(authStateProvider);
  final user = authState.valueOrNull;
  if (user == null) return authState.isLoading ? null : 0;
  return ref.watch(placeRepositoryProvider).countArchivedMyPlaces(user.id);
});

/// Selected ordering for the My Notes tab.
final myNotesSortProvider = StateProvider<NoteListSort>(
  (_) => NoteListSort.newest,
);

/// Selected ordering for the Archived tab.
final archivedMyNotesSortProvider = StateProvider<NoteListSort>(
  (_) => NoteListSort.archivedNewest,
);

// --- Note creation limit ---

/// The maximum number of active notes the current user may own, based on
/// premium status. Used to gate note creation client-side.
final noteLimitProvider = Provider<int>((ref) {
  final isPremium = ref.watch(isPremiumProvider).valueOrNull ?? false;
  return isPremium ? AppConfig.proNoteLimit : AppConfig.freeNoteLimit;
});

/// The current note-detail radius for the signed-in user.
final noteAccessRadiusMetersProvider = Provider<int>((ref) {
  final isPremium = ref.watch(isPremiumProvider).valueOrNull ?? false;
  return AppConfig.noteDetailAccessRadiusMetersFor(isPremium: isPremium);
});

// --- Messages ---

final messagesProvider = StreamProvider.autoDispose
    .family<List<MessageThreadItem>, String>((ref, placeId) {
      final user = ref.watch(authStateProvider).valueOrNull;
      if (user == null) return Stream.value(const []);
      return _afterBlockedUserIdsLoad(
        ref.watch(blockedUserIdsProvider),
        (blockedUserIds) => ref
            .watch(messageRepositoryProvider)
            .watchMessages(
              placeId: placeId,
              currentUserId: user.id,
              blockedUserIds: blockedUserIds,
            ),
      );
    });

final adminModerationReviewsProvider = FutureProvider.autoDispose
    .family<List<AdminModerationReviewEntity>, AdminModerationReviewStatus>((
      ref,
      status,
    ) {
      return ref
          .watch(adminModerationServiceProvider)
          .listReviews(status: status);
    });

// --- PRO subscription ---

// StreamProvider so the UI reacts instantly after a purchase or restore,
// without requiring an app restart.
final isPremiumProvider = StreamProvider<bool>((ref) {
  return ref.watch(subscriptionServiceProvider).isPremiumStream;
});

// --- Map Style ---

/// Persists and exposes the user's chosen map style.
final mapStyleProvider = StateNotifierProvider<MapStyleNotifier, MapStyle>((
  ref,
) {
  return MapStyleNotifier();
});

class MapStyleNotifier extends StateNotifier<MapStyle> {
  static const _prefKey = 'map_style';

  MapStyleNotifier() : super(MapStyle.standard) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null) {
      state = MapStyle.values.firstWhere(
        (s) => s.name == saved,
        orElse: () => MapStyle.standard,
      );
    }
  }

  Future<void> setStyle(MapStyle style) async {
    state = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, style.name);
  }
}

class MapLatLng {
  final double lat;
  final double lng;
  const MapLatLng(this.lat, this.lng);

  @override
  bool operator ==(Object other) =>
      other is MapLatLng && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);
}

MapLatLng latLng(double lat, double lng) => MapLatLng(lat, lng);

class MapCameraSnapshot {
  final MapLatLng center;
  final double zoom;

  const MapCameraSnapshot({required this.center, required this.zoom});
}

class MapPinSearchRadius {
  static const double _streetZoomThreshold = 15;
  static const double _neighborhoodZoomThreshold = 14;
  static const double _districtZoomThreshold = 13;
  static const double _cityZoomThreshold = 12;
  static const double _wideAreaZoomThreshold = 11;

  static const double _streetRadiusKm = 2;
  static const double _neighborhoodRadiusKm = 3;
  static const double _districtRadiusKm = 5;
  static const double _cityRadiusKm = 8;
  static const double _wideAreaRadiusKm = 12;
  static const double _regionRadiusKm = 20;

  static const double _metersPerKm = 1000;
  // Refresh after the user pans about one loaded radius away from the current
  // search center, so wide prefetches are reused instead of reloading eagerly.
  static const double _prefetchRefreshFraction = 1;
  static const double _minRefreshThresholdMeters = 500;
  static const double _maxRefreshThresholdMeters = 4000;

  /// Coarse zoom buckets avoid a fresh network request for tiny pinch-zoom
  /// differences while still loading a wider area as the user zooms out.
  static double forZoom(double zoom) {
    if (zoom >= _streetZoomThreshold) return _streetRadiusKm;
    if (zoom >= _neighborhoodZoomThreshold) return _neighborhoodRadiusKm;
    if (zoom >= _districtZoomThreshold) return _districtRadiusKm;
    if (zoom >= _cityZoomThreshold) return _cityRadiusKm;
    if (zoom >= _wideAreaZoomThreshold) return _wideAreaRadiusKm;
    return _regionRadiusKm;
  }

  static double refreshThresholdMeters(double radiusKm) {
    return (radiusKm * _metersPerKm * _prefetchRefreshFraction)
        .clamp(_minRefreshThresholdMeters, _maxRefreshThresholdMeters)
        .toDouble();
  }
}
