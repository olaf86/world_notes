import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../../config/runtime_mode.dart';
import '../../core/utils/image_upload_util.dart';
import '../../services/world_firebase_clients.dart';
import '../../domain/entities/place_entity.dart'
    show
        ArchivedPlacesPage,
        ClosedReason,
        NoteLockDraft,
        NoteLockType,
        NoteMember,
        NoteMembership,
        PlaceEntity,
        PlaceVisibility;
import '../../domain/entities/note_theme.dart';
import '../../domain/entities/note_visitor_entity.dart';
import '../../domain/entities/content_report.dart';
import '../../domain/entities/note_list_sort.dart';
import '../../domain/entities/pin_summary_entity.dart';
import '../../domain/repositories/place_repository.dart';
import '../models/note_visitor_model.dart';
import '../models/pin_summary_model.dart';
import '../models/place_model.dart';

// Required Firestore composite indexes are declared in firestore.indexes.json.
class PlaceRepositoryImpl implements PlaceRepository {
  final FirebaseFirestore _firestore;
  final WorldFunctionsClient _callables;
  final FirebaseStorage _storage;
  final _uuid = const Uuid();

  PlaceRepositoryImpl({
    required FirebaseFirestore firestore,
    required WorldFunctionsClient callables,
    required FirebaseStorage storage,
  }) : _firestore = firestore,
       _callables = callables,
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
    final result = await _callables
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
    if (screenshotMode) return;

    await _callables.httpsCallable('validateNoteAccess').call<void>({
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
    required NoteThemeId themeId,
    required String icon,
    required int expiryDays,
    DateTime? publishAt,
    PlaceVisibility visibility = PlaceVisibility.public,
    NoteLockDraft? lock,
  }) async {
    // All creation goes through the Cloud Function: it enforces the per-user
    // note cap in a transaction and computes the geohash server-side. Direct
    // client writes to `places` are denied by security rules.
    final callable = _callables.httpsCallable('createNote');
    final result = await callable.call<Map<String, dynamic>>({
      'latitude': latitude,
      'longitude': longitude,
      'title': title,
      'subtitle': subtitle,
      'colorHex': colorHex,
      'themeId': themeId.toJson(),
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
      await _callables.httpsCallable('setNotePinImage').call<void>({
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
  Future<void> reportNote({
    required String placeId,
    required ReportReasonCode reasonCode,
  }) async {
    await _callables.httpsCallable('reportNote').call<Map<String, dynamic>>({
      'placeId': placeId,
      'reasonCode': reasonCode.toJson(),
    });
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
  Future<int> countArchivedMyPlaces(String userId) async {
    final snap = await _maintainedPlacesQuery(
      userId,
      isArchived: true,
    ).count().get();
    return snap.count ?? 0;
  }

  @override
  Future<ArchivedPlacesPage> listArchivedMyPlaces({
    required String userId,
    required NoteListSort sort,
    Object? cursor,
    int limit = 50,
  }) async {
    assert(
      sort == NoteListSort.archivedNewest ||
          sort == NoteListSort.archivedOldest,
    );

    Query query = _maintainedPlacesQuery(userId, isArchived: true)
        .orderBy('archivedAt', descending: sort == NoteListSort.archivedNewest)
        .limit(limit + 1);
    if (cursor != null) {
      query = query.startAfterDocument(cursor as DocumentSnapshot);
    }

    final snap = await query.get();
    final pageDocs = snap.docs.take(limit).toList();
    return ArchivedPlacesPage(
      places: pageDocs
          .map((doc) => PlaceModel.fromFirestore(doc).toEntity())
          .toList(),
      nextCursor: pageDocs.isEmpty ? null : pageDocs.last,
      hasMore: snap.docs.length > limit,
    );
  }

  @override
  Future<void> archivePlace(String placeId) async {
    await _callables.httpsCallable('archiveNote').call<Map<String, dynamic>>({
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

  @override
  Future<void> setNoteTheme({
    required String placeId,
    required NoteThemeId themeId,
  }) async {
    await _callables.httpsCallable('setNoteTheme').call<void>({
      'placeId': placeId,
      'themeId': themeId.toJson(),
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
    await _callables
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
    await _callables.httpsCallable('unlockNote').call<Map<String, dynamic>>({
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

  // ── Likes ────────────────────────────────────────────────────────────────

  @override
  Stream<bool> watchNoteLike({
    required String placeId,
    required String userId,
  }) {
    return _places
        .doc(placeId)
        .collection('likes')
        .doc(userId)
        .snapshots()
        .map((doc) => doc.data()?['liked'] == true);
  }

  @override
  Future<void> setNoteLike({
    required String placeId,
    required bool liked,
  }) async {
    await _callables.httpsCallable('setNoteLike').call<Map<String, dynamic>>({
      'placeId': placeId,
      'liked': liked,
    });
  }

  // ── Invitations ───────────────────────────────────────────────────────────

  @override
  Future<String?> getInviteLink(String placeId) async {
    final result = await _callables
        .httpsCallable('getInviteLink')
        .call<Map<String, dynamic>>({'placeId': placeId});
    return result.data['token'] as String?;
  }

  @override
  Future<String> createInviteLink(String placeId) async {
    final result = await _callables
        .httpsCallable('createInviteLink')
        .call<Map<String, dynamic>>({'placeId': placeId});
    return result.data['token'] as String;
  }

  @override
  Future<void> revokeInvite(String placeId) async {
    await _callables.httpsCallable('revokeInvite').call<Map<String, dynamic>>({
      'placeId': placeId,
    });
  }

  @override
  Future<void> revokeNoteAccess({
    required String placeId,
    required String userId,
  }) async {
    await _callables
        .httpsCallable('revokeNoteAccess')
        .call<Map<String, dynamic>>({'placeId': placeId, 'userId': userId});
  }

  @override
  Future<void> grantNoteMaintainer({
    required String placeId,
    required String userId,
  }) async {
    await _callables
        .httpsCallable('grantNoteMaintainer')
        .call<Map<String, dynamic>>({'placeId': placeId, 'userId': userId});
  }

  @override
  Future<void> revokeNoteMaintainer({
    required String placeId,
    required String userId,
  }) async {
    await _callables
        .httpsCallable('revokeNoteMaintainer')
        .call<Map<String, dynamic>>({'placeId': placeId, 'userId': userId});
  }

  @override
  Future<String> claimInvite(String token) async {
    final result = await _callables
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
    if (screenshotMode) return;

    await _callables.httpsCallable('recordNoteVisit').call<void>({
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
    await _callables.httpsCallable('setFootprintEnabled').call<void>({
      'placeId': placeId,
      'enabled': enabled,
    });
  }
}
