import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/map_style.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../data/repositories/message_repository_impl.dart';
import '../../data/repositories/place_repository_impl.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/entities/place_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/message_repository.dart';
import '../../domain/repositories/place_repository.dart';
import '../../services/location_service.dart';
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

// --- Services ---

final locationServiceProvider = Provider<LocationService>(
  (_) => LocationService(),
);

final subscriptionServiceProvider = Provider<SubscriptionService>(
  (_) => SubscriptionService(),
);

// --- Repositories ---

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(
    auth: ref.watch(firebaseAuthProvider),
    googleSignIn: GoogleSignIn(),
    firestore: ref.watch(firestoreProvider),
    subscriptionService: ref.watch(subscriptionServiceProvider),
  );
});

final placeRepositoryProvider = Provider<PlaceRepository>((ref) {
  return PlaceRepositoryImpl(firestore: ref.watch(firestoreProvider));
});

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepositoryImpl(
    firestore: ref.watch(firestoreProvider),
    storage: ref.watch(firebaseStorageProvider),
  );
});

// --- Auth state ---

final authStateProvider = StreamProvider<UserEntity?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
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

// --- Places nearby ---

final placesNearbyProvider = StreamProvider.family<List<PlaceEntity>, MapLatLng>(
  (ref, latLng) {
    return ref
        .watch(placeRepositoryProvider)
        .watchPlacesNearby(
          latitude: latLng.lat,
          longitude: latLng.lng,
        );
  },
);

// --- Messages ---

final messagesProvider = StreamProvider.family<List<MessageEntity>, String>((
  ref,
  placeId,
) {
  return ref.watch(messageRepositoryProvider).watchMessages(placeId);
});

// --- Premium ---

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
