import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/image_upload_util.dart';
import '../../domain/entities/place_entity.dart'
    show
        ClosedReason,
        NoteLockDraft,
        NoteLockType,
        NoteMember,
        NoteMembership,
        PlaceEntity,
        PlaceVisibility;
import '../../domain/entities/nearby_notification_entity.dart';
import '../../domain/entities/note_visitor_entity.dart';
import '../../domain/entities/pin_summary_entity.dart';
import '../../domain/repositories/place_repository.dart';
import '../models/nearby_notification_model.dart';
import '../models/note_visitor_model.dart';
import '../models/pin_summary_model.dart';
import '../models/place_model.dart';

// Required Firestore composite indexes are declared in firestore.indexes.json.
class PlaceRepositoryImpl implements PlaceRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;
  final _uuid = const Uuid();

  PlaceRepositoryImpl({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required FirebaseStorage storage,
  }) : _firestore = firestore,
       _functions = functions,
       _storage = storage;

  CollectionReference get _places => _firestore.collection('places');

  @override
  Future<List<PinSummary>> listMapPins({
    required double centerLatitude,
    required double centerLongitude,
    required double userLatitude,
    required double userLongitude,
    required double searchRadiusKm,
  }) async {
    final result = await _functions
        .httpsCallable('listMapPins')
        .call<Map<String, dynamic>>({
          'centerLatitude': centerLatitude,
          'centerLongitude': centerLongitude,
          'userLatitude': userLatitude,
          'userLongitude': userLongitude,
          'searchRadiusKm': searchRadiusKm,
        });
    final pins = result.data['pins'] as List<dynamic>? ?? const [];
    return pins
        .whereType<Map>()
        .map(
          (json) => PinSummaryModel.fromJson(
            Map<String, dynamic>.from(json),
          ).toEntity(),
        )
        .toList();
  }

  @override
  Future<void> validateNoteAccess({
    required String placeId,
    required double latitude,
    required double longitude,
  }) async {
    await _functions.httpsCallable('validateNoteAccess').call<void>({
      'placeId': placeId,
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  @override
  Future<String> createNote({
    required double latitude,
    required double longitude,
    required String title,
    String? subtitle,
    required String colorHex,
    required String icon,
    required int expiryDays,
    DateTime? publishAt,
    PlaceVisibility visibility = PlaceVisibility.public,
    NoteLockDraft? lock,
  }) async {
    // All creation goes through the Cloud Function: it enforces the per-user
    // note cap in a transaction and computes the geohash server-side. Direct
    // client writes to `places` are denied by security rules.
    final callable = _functions.httpsCallable('createNote');
    final result = await callable.call<Map<String, dynamic>>({
      'latitude': latitude,
      'longitude': longitude,
      'title': title,
      'subtitle': subtitle,
      'colorHex': colorHex,
      'icon': icon,
      'expiryDays': expiryDays,
      if (publishAt != null)
        'publishAtMillis': publishAt.millisecondsSinceEpoch,
      'visibility': visibility.toJson(),
      if (lock != null)
        'lock': {
          'lockType': lock.lockType.toJson(),
          'password': lock.secret,
          'lockHint': lock.lockHint,
        },
    });
    return result.data['placeId'] as String;
  }

  @override
  Future<void> setNotePinImage({
    required String placeId,
    required String userId,
    required List<int> thumbnailBytes,
  }) async {
    final path = ImageUploadUtil.pinThumbnailStoragePath(
      placeId: placeId,
      userId: userId,
      imageId: _uuid.v7(),
    );
    final ref = _storage.ref(path);
    try {
      await ref.putData(
        Uint8List.fromList(thumbnailBytes),
        SettableMetadata(contentType: 'image/webp'),
      );
      await _functions.httpsCallable('setNotePinImage').call<void>({
        'placeId': placeId,
        'pinImageStoragePath': path,
      });
    } catch (_) {
      try {
        await ref.delete();
      } catch (_) {
        // Best effort cleanup. The callable is still the source of truth for
        // whether a thumbnail is attached to the note.
      }
      rethrow;
    }
  }

  @override
  Future<PlaceEntity?> getPlace(String placeId) async {
    final doc = await _places.doc(placeId).get();
    if (!doc.exists) return null;
    return PlaceModel.fromFirestore(doc).toEntity();
  }

  @override
  Stream<PlaceEntity?> watchPlace(String placeId) {
    return _places
        .doc(placeId)
        .snapshots()
        .map(
          (doc) => doc.exists ? PlaceModel.fromFirestore(doc).toEntity() : null,
        );
  }

  // ── Maintainer queries ────────────────────────────────────────────────────

  Query _maintainedPlacesQuery(String userId, {required bool isArchived}) =>
      _places
          .where('maintainerIds', arrayContains: userId)
          .where('isArchived', isEqualTo: isArchived);

  List<PlaceEntity> _collectMyPlaces(QuerySnapshot snap) {
    final places = snap.docs
        .map((doc) => PlaceModel.fromFirestore(doc).toEntity())
        .where((place) => !place.isArchived && !place.isExpired)
        .toList();
    places.sort((a, b) {
      final aTime = a.lastMessageAt ?? a.createdAt;
      final bTime = b.lastMessageAt ?? b.createdAt;
      return bTime.compareTo(aTime);
    });
    return places;
  }

  List<PlaceEntity> _collectArchivedMyPlaces(QuerySnapshot snap) {
    final places = snap.docs
        .map((doc) => PlaceModel.fromFirestore(doc).toEntity())
        .where((place) => place.isArchived)
        .toList();
    places.sort((a, b) {
      final aTime = a.archivedAt ?? a.expiresAt;
      final bTime = b.archivedAt ?? b.expiresAt;
      return bTime.compareTo(aTime);
    });
    return places;
  }

  @override
  Future<int> countUserActivePlaces(String userId) async {
    final snap = await _places
        .where('maintainerIds', arrayContains: userId)
        .where('isArchived', isEqualTo: false)
        .count()
        .get();
    return snap.count ?? 0;
  }

  @override
  Stream<List<PlaceEntity>> watchMyPlaces(String userId) {
    return _maintainedPlacesQuery(
      userId,
      isArchived: false,
    ).snapshots().map(_collectMyPlaces);
  }

  @override
  Future<List<PlaceEntity>> getMyPlaces(String userId) async {
    final snap = await _maintainedPlacesQuery(userId, isArchived: false).get();
    return _collectMyPlaces(snap);
  }

  @override
  Stream<List<PlaceEntity>> watchArchivedMyPlaces(String userId) {
    return _maintainedPlacesQuery(
      userId,
      isArchived: true,
    ).snapshots().map(_collectArchivedMyPlaces);
  }

  @override
  Future<void> archivePlace(String placeId) async {
    await _functions.httpsCallable('archiveNote').call<Map<String, dynamic>>({
      'placeId': placeId,
    });
  }

  // ── Writability ───────────────────────────────────────────────────────────

  @override
  Future<void> closePlace(
    String placeId, {
    required ClosedReason reason,
  }) async {
    await _places.doc(placeId).update({
      'isOpen': false,
      'closedReason': reason.toJson(),
      'closedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> reopenPlace(String placeId) async {
    await _places.doc(placeId).update({
      'isOpen': true,
      'closedReason': FieldValue.delete(),
      'closedAt': FieldValue.delete(),
    });
  }

  // ── Private access ──────────────────────────────────────────────────────

  @override
  Future<void> setNotePassword({
    required String placeId,
    required String password,
    required NoteLockType lockType,
    String? lockHint,
  }) async {
    await _functions
        .httpsCallable('setNotePassword')
        .call<Map<String, dynamic>>({
          'placeId': placeId,
          'password': password,
          'lockType': lockType.toJson(),
          'lockHint': lockHint,
        });
  }

  @override
  Future<void> unlockNote({
    required String placeId,
    required String password,
  }) async {
    await _functions.httpsCallable('unlockNote').call<Map<String, dynamic>>({
      'placeId': placeId,
      'password': password,
    });
  }

  @override
  Stream<NoteMembership?> watchMembership({
    required String placeId,
    required String userId,
  }) {
    return _places
        .doc(placeId)
        .collection('members')
        .doc(userId)
        .snapshots()
        .map((doc) {
          if (!doc.exists) return null;
          final data = doc.data()!;
          return NoteMembership(
            invited: data['invited'] as bool? ?? false,
            viaPasswordVersion: (data['viaPasswordVersion'] as int?) ?? -1,
          );
        });
  }

  // ── Invitations ───────────────────────────────────────────────────────────

  @override
  Future<String?> getInviteLink(String placeId) async {
    final result = await _functions
        .httpsCallable('getInviteLink')
        .call<Map<String, dynamic>>({'placeId': placeId});
    return result.data['token'] as String?;
  }

  @override
  Future<String> createInviteLink(String placeId) async {
    final result = await _functions
        .httpsCallable('createInviteLink')
        .call<Map<String, dynamic>>({'placeId': placeId});
    return result.data['token'] as String;
  }

  @override
  Future<void> revokeInvite(String placeId) async {
    await _functions.httpsCallable('revokeInvite').call<Map<String, dynamic>>({
      'placeId': placeId,
    });
  }

  @override
  Future<void> revokeNoteAccess({
    required String placeId,
    required String userId,
  }) async {
    await _functions
        .httpsCallable('revokeNoteAccess')
        .call<Map<String, dynamic>>({'placeId': placeId, 'userId': userId});
  }

  @override
  Future<void> grantNoteMaintainer({
    required String placeId,
    required String userId,
  }) async {
    await _functions
        .httpsCallable('grantNoteMaintainer')
        .call<Map<String, dynamic>>({'placeId': placeId, 'userId': userId});
  }

  @override
  Future<void> revokeNoteMaintainer({
    required String placeId,
    required String userId,
  }) async {
    await _functions
        .httpsCallable('revokeNoteMaintainer')
        .call<Map<String, dynamic>>({'placeId': placeId, 'userId': userId});
  }

  @override
  Future<String> claimInvite(String token) async {
    final result = await _functions
        .httpsCallable('claimInvite')
        .call<Map<String, dynamic>>({'token': token});
    return result.data['placeId'] as String;
  }

  @override
  Stream<List<NoteMember>> watchMembers(String placeId) {
    return _places
        .doc(placeId)
        .collection('members')
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) {
            final data = doc.data();
            return NoteMember(
              userId: doc.id,
              displayName: data['displayName'] as String?,
              invited: data['invited'] as bool? ?? false,
              isMaintainer: data['isMaintainer'] as bool? ?? false,
            );
          }).toList(),
        );
  }

  @override
  Future<void> recordNoteVisit(String placeId) async {
    await _functions.httpsCallable('recordNoteVisit').call<void>({
      'placeId': placeId,
    });
  }

  @override
  Stream<List<NoteVisitor>> watchRecentVisitors({
    required String placeId,
    required int limit,
  }) {
    return _places
        .doc(placeId)
        .collection('visitors')
        .orderBy('lastVisitedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(_visitorsFromSnapshot);
  }

  @override
  Stream<List<NoteVisitor>> watchVisitors({
    required String placeId,
    required NoteVisitorSort sort,
  }) {
    final query = switch (sort) {
      NoteVisitorSort.latest =>
        _places
            .doc(placeId)
            .collection('visitors')
            .orderBy('lastVisitedAt', descending: true),
      NoteVisitorSort.visitCount =>
        _places
            .doc(placeId)
            .collection('visitors')
            .orderBy('visitCount', descending: true),
    };
    return query.snapshots().map(_visitorsFromSnapshot);
  }

  List<NoteVisitor> _visitorsFromSnapshot(QuerySnapshot snap) {
    return snap.docs
        .map(NoteVisitorModel.fromFirestore)
        .map((model) => model.toEntity())
        .toList();
  }

  @override
  Future<void> setFootprintEnabled({
    required String placeId,
    required bool enabled,
  }) async {
    await _functions.httpsCallable('setFootprintEnabled').call<void>({
      'placeId': placeId,
      'enabled': enabled,
    });
  }

  @override
  Stream<List<NearbyNotificationPlace>> watchNearbyNotificationPlaces(
    String userId,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('nearbyNotificationPlaces')
        .where('enabled', isEqualTo: true)
        .where('state', isEqualTo: 'active')
        .snapshots()
        .map((snap) {
          final now = DateTime.now();
          final places = snap.docs
              .map((doc) => NearbyNotificationModel.fromFirestore(doc))
              .map((model) => model.toEntity())
              .where((place) => place.isActive && place.expiresAt.isAfter(now))
              .toList();
          places.sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
          return places;
        });
  }

  @override
  Stream<NearbyNotificationPlace?> watchNearbyNotificationPlace({
    required String userId,
    required String placeId,
  }) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('nearbyNotificationPlaces')
        .doc(placeId)
        .snapshots()
        .map(
          (doc) => doc.exists
              ? NearbyNotificationModel.fromFirestore(doc).toEntity()
              : null,
        );
  }

  @override
  Future<void> setNearbyNotification({
    required String placeId,
    required bool enabled,
  }) async {
    await _functions.httpsCallable('setNearbyNotification').call<void>({
      'placeId': placeId,
      'enabled': enabled,
    });
  }

  @override
  Future<void> markNearbyNotificationRead(String placeId) async {
    await _functions.httpsCallable('markNearbyNotificationRead').call<void>({
      'placeId': placeId,
    });
  }

  @override
  Future<void> markNearbyNotificationInRange({
    required String placeId,
    required bool inRange,
  }) async {
    await _functions.httpsCallable('markNearbyNotificationInRange').call<void>({
      'placeId': placeId,
      'inRange': inRange,
    });
  }

  @override
  Future<NearbyUnreadResult> checkNearbyUnread(String placeId) async {
    final result = await _functions
        .httpsCallable('checkNearbyUnread')
        .call<Map<String, dynamic>>({'placeId': placeId});
    return NearbyUnreadResult(
      hasUnread: result.data['hasUnread'] == true,
      placeId: result.data['placeId'] as String?,
      messageId: result.data['messageId'] as String?,
      title: result.data['title'] as String?,
    );
  }
}
