import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_config.dart';
import '../../config/regions.dart';
import '../../config/runtime_mode.dart';
import '../../core/map_style.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../data/repositories/message_repository_impl.dart';
import '../../data/repositories/notice_repository_impl.dart';
import '../../data/repositories/place_repository_impl.dart';
import '../../domain/entities/nearby_notification_entity.dart';
import '../../domain/entities/admin_moderation_review_entity.dart';
import '../../domain/entities/message_thread_item.dart';
import '../../domain/entities/note_visitor_entity.dart';
import '../../domain/entities/notice_entity.dart';
import '../../domain/entities/pin_summary_entity.dart';
import '../../domain/entities/place_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/message_repository.dart';
import '../../domain/repositories/notice_repository.dart';
import '../../domain/repositories/place_repository.dart';
import '../../services/location_service.dart';
import '../../services/admin_moderation_service.dart';
import '../../services/message_image_service.dart';
import '../../services/my_notes_notification_service.dart';
import '../../services/native_geofence_service.dart';
import '../../services/nearby_notification_service.dart';
import '../../services/nearby_proximity_monitor.dart';
import '../../services/notice_notification_service.dart';
import '../../services/subscription_service.dart';

// --- Infrastructure ---

final firestoreProvider = Provider<FirebaseFirestore>(
  (_) => FirebaseFirestore.instance,
);

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (_) => FirebaseAuth.instance,
);

final firebaseStorageProvider = Provider<FirebaseStorage>(
  (_) => FirebaseStorage.instance,
);

final firebaseMessagingProvider = Provider<FirebaseMessaging>(
  (_) => FirebaseMessaging.instance,
);

final firebaseCrashlyticsProvider = Provider<FirebaseCrashlytics>(
  (_) => FirebaseCrashlytics.instance,
);

final localNotificationsProvider = Provider<FlutterLocalNotificationsPlugin>(
  (_) => FlutterLocalNotificationsPlugin(),
);

// The client must target a region where the functions are actually deployed,
// or callable lookups 404. The region is resolved by [effectiveRegionProvider]
// (manual override > nearest available to current location > default).
final firebaseFunctionsProvider = Provider<FirebaseFunctions>((ref) {
  final region = ref.watch(effectiveRegionProvider);
  return FirebaseFunctions.instanceFor(region: region);
});

// --- Services ---

final locationServiceProvider = Provider<LocationService>(
  (_) => LocationService(),
);

final subscriptionServiceProvider = Provider<SubscriptionService>(
  (_) => SubscriptionService(),
);

final messageImageServiceProvider = Provider<MessageImageService>((ref) {
  final service = MessageImageService(
    storage: ref.watch(firebaseStorageProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final messageImageUrlProvider = FutureProvider.autoDispose
    .family<String, String>((ref, storagePath) {
      return ref.watch(messageImageServiceProvider).downloadUrl(storagePath);
    });

final myNotesNotificationServiceProvider = Provider<MyNotesNotificationService>(
  (ref) {
    final service = MyNotesNotificationService(
      messaging: ref.watch(firebaseMessagingProvider),
      functions: ref.watch(firebaseFunctionsProvider),
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

final nearbyNotificationServiceProvider = Provider<NearbyNotificationService>((
  ref,
) {
  final service = NearbyNotificationService(
    notifications: ref.watch(localNotificationsProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final adminModerationServiceProvider = Provider<AdminModerationService>((ref) {
  return AdminModerationService(
    functions: ref.watch(firebaseFunctionsProvider),
  );
});

final nativeGeofenceServiceProvider = Provider<NativeGeofenceService>((ref) {
  final service = NativeGeofenceService();
  ref.onDispose(service.dispose);
  return service;
});

// --- Repositories ---

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(
    auth: ref.watch(firebaseAuthProvider),
    googleSignIn: GoogleSignIn(),
    firestore: ref.watch(firestoreProvider),
    functions: ref.watch(firebaseFunctionsProvider),
    myNotesNotificationService: ref.watch(myNotesNotificationServiceProvider),
    subscriptionService: ref.watch(subscriptionServiceProvider),
    messageImageService: ref.watch(messageImageServiceProvider),
  );
});

final placeRepositoryProvider = Provider<PlaceRepository>((ref) {
  return PlaceRepositoryImpl(
    firestore: ref.watch(firestoreProvider),
    functions: ref.watch(firebaseFunctionsProvider),
    storage: ref.watch(firebaseStorageProvider),
  );
});

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepositoryImpl(
    firestore: ref.watch(firestoreProvider),
    functions: ref.watch(firebaseFunctionsProvider),
    storage: ref.watch(firebaseStorageProvider),
  );
});

final noticeRepositoryProvider = Provider<NoticeRepository>((ref) {
  return NoticeRepositoryImpl(firestore: ref.watch(firestoreProvider));
});

// --- Auth state ---

final authStateProvider = StreamProvider<UserEntity?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
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

// --- Notifications ---

final myNotesNotificationEnabledProvider = StreamProvider<bool>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(false);
  return ref
      .watch(firestoreProvider)
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
      .watch(firestoreProvider)
      .collection('users')
      .doc(user.id)
      .collection('notificationSettings')
      .doc('main')
      .snapshots()
      .map((snap) => snap.data()?['myNotesPreviewEnabled'] != false);
});

final nearbyNotificationPlacesProvider =
    StreamProvider<List<NearbyNotificationPlace>>((ref) {
      final user = ref.watch(authStateProvider).valueOrNull;
      if (user == null) return Stream.value(const []);
      return ref
          .watch(placeRepositoryProvider)
          .watchNearbyNotificationPlaces(user.id);
    });

final nearbyNotificationPlaceProvider =
    StreamProvider.family<NearbyNotificationPlace?, String>((ref, placeId) {
      final user = ref.watch(authStateProvider).valueOrNull;
      if (user == null) return Stream.value(null);
      return ref
          .watch(placeRepositoryProvider)
          .watchNearbyNotificationPlace(userId: user.id, placeId: placeId);
    });

/// Runtime view used by [NearbyProximityMonitor].
///
/// The geofence radius is not alert state: it is the current entitlement policy.
/// Keeping it derived means PRO upgrades and downgrades take effect without
/// rewriting every saved nearby-alert document.
final _nearbyNotificationMonitorPlacesProvider =
    Provider<List<NearbyNotificationPlace>>((ref) {
      final places = ref.watch(nearbyNotificationPlacesProvider).valueOrNull;
      if (places == null || places.isEmpty) return const [];
      final radiusMeters = ref.watch(noteAccessRadiusMetersProvider);
      return _withCurrentNearbyRadius(places, radiusMeters);
    });

List<NearbyNotificationPlace> _withCurrentNearbyRadius(
  List<NearbyNotificationPlace> places,
  int radiusMeters,
) {
  return [for (final place in places) place.withRadiusMeters(radiusMeters)];
}

final noticesProvider = StreamProvider<List<NoticeEntity>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.watch(noticeRepositoryProvider).watchNotices(user.id);
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

final _nearbySharedPositionProvider = Provider<AsyncValue<Position>?>((ref) {
  final places = ref.watch(_nearbyNotificationMonitorPlacesProvider);
  if (places.isEmpty) return null;
  return ref.watch(positionStreamProvider);
});

final nearbyProximityMonitorProvider = Provider<void>((ref) {
  ref.keepAlive();
  final monitor = NearbyProximityMonitor(
    crashlytics: ref.read(firebaseCrashlyticsProvider),
    placeRepository: ref.read(placeRepositoryProvider),
    nativeGeofenceService: ref.read(nativeGeofenceServiceProvider),
    nearbyNotificationService: ref.read(nearbyNotificationServiceProvider),
  )..start();

  ref.listen<List<NearbyNotificationPlace>>(
    _nearbyNotificationMonitorPlacesProvider,
    (_, next) => monitor.updatePlaces(next),
    fireImmediately: true,
  );
  ref.listen<AsyncValue<Position>?>(_nearbySharedPositionProvider, (_, next) {
    next?.whenData(monitor.updatePosition);
  });
  ref.onDispose(monitor.dispose);
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

/// Live stream of a single place by id (null if it doesn't exist).
final placeProvider = StreamProvider.family<PlaceEntity?, String>((
  ref,
  placeId,
) {
  return ref.watch(placeRepositoryProvider).watchPlace(placeId);
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
      return ref
          .watch(placeRepositoryProvider)
          .watchRecentVisitors(
            placeId: placeId,
            limit: AppConfig.visitorPreviewExpandedMax,
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
      return ref
          .watch(placeRepositoryProvider)
          .watchVisitors(placeId: request.placeId, sort: request.sort);
    });

/// Active notes owned by the current user. Used by the My Notes read-only
/// destination; returns an empty stream while signed out.
final myPlacesProvider = StreamProvider<List<PlaceEntity>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.watch(placeRepositoryProvider).watchMyPlaces(user.id);
});

/// Archived notes owned by the current user; returns an empty stream while
/// signed out.
final archivedMyPlacesProvider = StreamProvider<List<PlaceEntity>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.watch(placeRepositoryProvider).watchArchivedMyPlaces(user.id);
});

// --- Note creation limit ---

/// The maximum number of active notes the current user may own, based on
/// premium status. Used to gate note creation client-side.
final noteLimitProvider = Provider<int>((ref) {
  final isPremium = ref.watch(isPremiumProvider).valueOrNull ?? false;
  return isPremium ? AppConfig.proNoteLimit : AppConfig.freeNoteLimit;
});

/// The current note-detail and nearby-alert radius for the signed-in user.
final noteAccessRadiusMetersProvider = Provider<int>((ref) {
  final isPremium = ref.watch(isPremiumProvider).valueOrNull ?? false;
  return AppConfig.noteDetailAccessRadiusMetersFor(isPremium: isPremium);
});

// --- Messages ---

final messagesProvider = StreamProvider.autoDispose
    .family<List<MessageThreadItem>, String>((ref, placeId) {
      final user = ref.watch(authStateProvider).valueOrNull;
      if (user == null) return Stream.value(const []);
      return ref
          .watch(messageRepositoryProvider)
          .watchMessages(placeId: placeId, currentUserId: user.id);
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

// --- Region selection ---

/// User's region preference: a region id to force, or null for "Auto"
/// (nearest available to the current location). Persisted across launches.
class RegionPreferenceNotifier extends StateNotifier<String?> {
  static const _prefKey = 'region_override';

  RegionPreferenceNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    // Ignore a saved region that no longer exists / is unavailable.
    if (saved != null && (Regions.byId(saved)?.available ?? false)) {
      state = saved;
    }
  }

  /// Pass a region id to pin it, or null to return to Auto.
  Future<void> setOverride(String? regionId) async {
    state = regionId;
    final prefs = await SharedPreferences.getInstance();
    if (regionId == null) {
      await prefs.remove(_prefKey);
    } else {
      await prefs.setString(_prefKey, regionId);
    }
  }
}

final regionPreferenceProvider =
    StateNotifierProvider<RegionPreferenceNotifier, String?>(
      (ref) => RegionPreferenceNotifier(),
    );

/// The region the client actually targets:
///   1. a valid, available manual override, else
///   2. the nearest available region to the current location, else
///   3. the default region.
final effectiveRegionProvider = Provider<String>((ref) {
  final override = ref.watch(regionPreferenceProvider);
  if (override != null && (Regions.byId(override)?.available ?? false)) {
    return override;
  }
  final pos = ref.watch(anchorPositionProvider);
  if (pos != null) {
    return Regions.nearestAvailableId(pos.latitude, pos.longitude);
  }
  return Regions.defaultId;
});

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
