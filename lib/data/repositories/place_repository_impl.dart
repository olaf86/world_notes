import 'dart:async';
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
import '../../domain/entities/note_administrator_entity.dart';
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
  final WorldFunctionsClient _functions;
  final FirebaseStorage _storage;
  final _uuid = const Uuid();

  PlaceRepositoryImpl({
    required FirebaseFirestore firestore,
    required WorldFunctionsClient functions,
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
    if (screenshotMode) return;

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
    required NoteThemeId themeId,
    required String icon,
    required int expiryDays,
    DateTime? publishAt,
    PlaceVisibility visibility = PlaceVisibility.public,
    NoteLockDraft? lock,
  }) async {
    // The client-generated UUID v7 makes a timed-out Callable retry resolve to
    // the same server document. The Function still owns quota enforcement and
    // every Firestore write; direct client creation remains denied by Rules.
    final placeId = _uuid.v7();
    final callable = _functions.httpsCallable('createNote');
    final result = await callable.call<Map<String, dynamic>>({
      'placeId': placeId,
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
      await _functions.httpsCallable('setNotePinImage').call<void>({
        'placeId': placeId,
        'pinImageStoragePath': path,
      });
    } catch (_) {
      // The regional orphan-upload sweeper owns immutable object cleanup.
      rethrow;
    }
  }

  @override
  Future<void> reportNote({
    required String placeId,
    required ReportReasonCode reasonCode,
  }) async {
    await _functions.httpsCallable('reportNote').call<Map<String, dynamic>>({
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

  Query _createdPlacesQuery(String userId, {required bool isArchived}) =>
      _places
          .where('createdByUserId', isEqualTo: userId)
          .where('isArchived', isEqualTo: isArchived);

  Query _administratorRecordsQuery(String userId) => _firestore
      .collectionGroup('administrators')
      .where('userId', isEqualTo: userId);

  Set<String> _administratorPlaceIds(QuerySnapshot snapshot) {
    return snapshot.docs.map((document) {
      final place = document.reference.parent.parent;
      if (place == null || place.parent.id != 'places') {
        throw StateError('Administrator record has an invalid place path.');
      }
      return place.id;
    }).toSet();
  }

  Future<List<DocumentSnapshot>> _delegatedPlaceDocuments(
    QuerySnapshot administratorRecords,
  ) async {
    final placeIds = _administratorPlaceIds(administratorRecords);
    if (placeIds.isEmpty) return const [];
    final documents = await Future.wait(
      placeIds.map((placeId) async {
        try {
          return await _places.doc(placeId).get();
        } on FirebaseException catch (error) {
          // A block is enforced before its asynchronous relationship cleanup.
          // During that short window the relationship is discoverable, while
          // the parent note correctly denies an exact read. Treat it as absent.
          if (error.code == 'permission-denied') return null;
          rethrow;
        }
      }),
    );
    return documents.whereType<DocumentSnapshot>().toList();
  }

  Iterable<PlaceEntity> _placeEntities(
    Iterable<DocumentSnapshot> documents,
  ) sync* {
    for (final document in documents) {
      if (document.exists) {
        yield PlaceModel.fromFirestore(document).toEntity();
      }
    }
  }

  List<PlaceEntity> _collectMyPlaces(Iterable<PlaceEntity> values) {
    final byId = {for (final place in values) place.id: place};
    final places = byId.values
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
    if (userId.isEmpty) return 0;
    final snapshot = await _createdPlacesQuery(
      userId,
      isArchived: false,
    ).count().get();
    return snapshot.count ?? 0;
  }

  @override
  Stream<List<PlaceEntity>> watchMyPlaces(String userId) {
    if (userId.isEmpty) return Stream.value(const []);

    late final StreamController<List<PlaceEntity>> controller;
    QuerySnapshot? createdSnapshot;
    QuerySnapshot? administratorSnapshot;
    StreamSubscription<QuerySnapshot>? createdSubscription;
    StreamSubscription<QuerySnapshot>? administratorSubscription;
    final delegatedSnapshots = <String, DocumentSnapshot>{};
    final inaccessibleDelegatedIds = <String>{};
    final delegatedSubscriptions =
        <String, StreamSubscription<DocumentSnapshot>>{};

    void emitIfReady() {
      final created = createdSnapshot;
      final administrators = administratorSnapshot;
      if (created == null || administrators == null) return;
      final delegatedIds = _administratorPlaceIds(administrators);
      if (!delegatedIds.every(
        (placeId) =>
            delegatedSnapshots.containsKey(placeId) ||
            inaccessibleDelegatedIds.contains(placeId),
      )) {
        return;
      }
      controller.add(
        _collectMyPlaces([
          ..._placeEntities(created.docs),
          ..._placeEntities(
            delegatedIds
                .map((placeId) => delegatedSnapshots[placeId])
                .whereType<DocumentSnapshot>(),
          ),
        ]),
      );
    }

    void synchronizeDelegatedSubscriptions() {
      final administrators = administratorSnapshot;
      if (administrators == null) return;
      final delegatedIds = _administratorPlaceIds(administrators);
      final staleIds = delegatedSubscriptions.keys
          .where((placeId) => !delegatedIds.contains(placeId))
          .toList();
      for (final placeId in staleIds) {
        final subscription = delegatedSubscriptions.remove(placeId);
        delegatedSnapshots.remove(placeId);
        inaccessibleDelegatedIds.remove(placeId);
        if (subscription != null) unawaited(subscription.cancel());
      }
      for (final placeId in delegatedIds) {
        if (delegatedSubscriptions.containsKey(placeId)) continue;
        late final StreamSubscription<DocumentSnapshot> subscription;
        subscription = _places
            .doc(placeId)
            .snapshots()
            .listen(
              (snapshot) {
                if (delegatedSubscriptions[placeId] != subscription) return;
                inaccessibleDelegatedIds.remove(placeId);
                delegatedSnapshots[placeId] = snapshot;
                emitIfReady();
              },
              onError: (Object error, StackTrace stackTrace) {
                if (delegatedSubscriptions[placeId] != subscription) return;
                if (error is FirebaseException &&
                    error.code == 'permission-denied') {
                  delegatedSnapshots.remove(placeId);
                  inaccessibleDelegatedIds.add(placeId);
                  emitIfReady();
                  return;
                }
                controller.addError(error, stackTrace);
              },
            );
        delegatedSubscriptions[placeId] = subscription;
      }
      emitIfReady();
    }

    controller = StreamController<List<PlaceEntity>>(
      onListen: () {
        createdSubscription = _createdPlacesQuery(userId, isArchived: false)
            .snapshots()
            .listen((snapshot) {
              createdSnapshot = snapshot;
              emitIfReady();
            }, onError: controller.addError);
        administratorSubscription = _administratorRecordsQuery(userId)
            .snapshots()
            .listen((snapshot) {
              administratorSnapshot = snapshot;
              synchronizeDelegatedSubscriptions();
            }, onError: controller.addError);
      },
      onCancel: () async {
        final delegated = delegatedSubscriptions.values.toList();
        delegatedSubscriptions.clear();
        delegatedSnapshots.clear();
        inaccessibleDelegatedIds.clear();
        await Future.wait([
          if (createdSubscription != null) createdSubscription!.cancel(),
          if (administratorSubscription != null)
            administratorSubscription!.cancel(),
          ...delegated.map((subscription) => subscription.cancel()),
        ]);
      },
    );
    return controller.stream;
  }

  @override
  Future<List<PlaceEntity>> getMyPlaces(String userId) async {
    if (userId.isEmpty) return const [];
    final snapshots = await Future.wait([
      _createdPlacesQuery(userId, isArchived: false).get(),
      _administratorRecordsQuery(userId).get(),
    ]);
    final delegated = await _delegatedPlaceDocuments(snapshots[1]);
    return _collectMyPlaces([
      ..._placeEntities(snapshots[0].docs),
      ..._placeEntities(delegated),
    ]);
  }

  @override
  Future<int> countArchivedMyPlaces(String userId) async {
    if (userId.isEmpty) return 0;
    final createdCount = await _createdPlacesQuery(
      userId,
      isArchived: true,
    ).count().get();
    final administratorRecords = await _administratorRecordsQuery(userId).get();
    final delegated = await _delegatedPlaceDocuments(administratorRecords);
    final delegatedIds = _placeEntities(delegated)
        .where((place) => place.isArchived && place.createdByUserId != userId)
        .map((place) => place.id)
        .toSet();
    return (createdCount.count ?? 0) + delegatedIds.length;
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

    if (userId.isEmpty || limit <= 0) {
      return const ArchivedPlacesPage(
        places: [],
        nextCursor: null,
        hasMore: false,
      );
    }
    final previous = cursor == null
        ? null
        : cursor as _ArchivedMaintainedNotesCursor;
    if (previous != null && previous.sort != sort) {
      throw ArgumentError('Archive cursor sort does not match the request.');
    }
    final buffered = [...?previous?.bufferedPlaces];
    DocumentSnapshot? lastCreatedDocument = previous?.lastCreatedDocument;
    var hasMoreCreated = previous?.hasMoreCreated ?? true;

    if (cursor == null) {
      final administratorRecords = await _administratorRecordsQuery(
        userId,
      ).get();
      final delegated = await _delegatedPlaceDocuments(administratorRecords);
      buffered.addAll(
        _placeEntities(
          delegated,
        ).where((place) => place.isArchived && place.createdByUserId != userId),
      );
    }

    if (hasMoreCreated) {
      final descending = sort == NoteListSort.archivedNewest;
      Query query = _createdPlacesQuery(userId, isArchived: true)
          .orderBy('archivedAt', descending: descending)
          .orderBy(FieldPath.documentId, descending: descending)
          .limit(limit + 1);
      if (lastCreatedDocument != null) {
        query = query.startAfterDocument(lastCreatedDocument);
      }
      final created = await query.get();
      buffered.addAll(_placeEntities(created.docs));
      if (created.docs.isNotEmpty) {
        lastCreatedDocument = created.docs.last;
      }
      hasMoreCreated = created.docs.length > limit;
    }

    final sorted = _sortArchivedMaintainedPlaces(buffered, sort);
    final page = sorted.take(limit).toList();
    final remaining = sorted.skip(page.length).toList();
    final hasMore = hasMoreCreated || remaining.isNotEmpty;
    return ArchivedPlacesPage(
      places: page,
      nextCursor: hasMore
          ? _ArchivedMaintainedNotesCursor(
              sort: sort,
              bufferedPlaces: remaining,
              lastCreatedDocument: lastCreatedDocument,
              hasMoreCreated: hasMoreCreated,
            )
          : null,
      hasMore: hasMore,
    );
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

  @override
  Future<void> setNoteTheme({
    required String placeId,
    required NoteThemeId themeId,
  }) async {
    await _functions.httpsCallable('setNoteTheme').call<void>({
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
    await _functions.httpsCallable('setNoteLike').call<Map<String, dynamic>>({
      'placeId': placeId,
      'liked': liked,
    });
  }

  // ── Note administrators ──────────────────────────────────────────────────

  @override
  Stream<bool> watchNoteAdministratorAuthority({
    required String placeId,
    required String userId,
  }) {
    return _places
        .doc(placeId)
        .collection('administrators')
        .doc(userId)
        .snapshots()
        .map(
          (document) => document.exists && document.data()?['userId'] == userId,
        );
  }

  @override
  Future<NoteAdministratorInvitationResult> createNoteAdministratorInvitation({
    required String placeId,
    required String targetUid,
  }) async {
    final result = await _functions
        .httpsCallable('createNoteAdministratorInvitation')
        .call<Map<String, dynamic>>({
          'placeId': placeId,
          'targetUid': targetUid,
        });
    return NoteAdministratorInvitationResult(
      token: _requiredString(result.data, 'token'),
      placeId: _requiredString(result.data, 'placeId'),
      targetUid: _requiredString(result.data, 'targetUid'),
      expiresAt: _requiredDate(result.data, 'expiresAtMillis'),
    );
  }

  @override
  Future<NoteAdministratorInvitationPreview> previewNoteAdministratorInvitation(
    String token,
  ) async {
    final result = await _functions
        .httpsCallable('previewNoteAdministratorInvitation')
        .call<Map<String, dynamic>>({'token': token});
    return NoteAdministratorInvitationPreview(
      worldId: _functions.worldId,
      placeId: _requiredString(result.data, 'placeId'),
      title: _requiredString(result.data, 'title'),
      invitedByUid: _requiredString(result.data, 'invitedByUid'),
      status: NoteAdministratorInvitationStatus.parse(result.data['status']),
      expiresAt: _requiredDate(result.data, 'expiresAtMillis'),
      worldReady: result.data['worldReady'] == true,
      canAccept: result.data['canAccept'] == true,
    );
  }

  @override
  Future<String> acceptNoteAdministratorInvitation(String token) async {
    final result = await _functions
        .httpsCallable('acceptNoteAdministratorInvitation')
        .call<Map<String, dynamic>>({'token': token});
    return _requiredString(result.data, 'placeId');
  }

  @override
  Future<void> revokeNoteAdministratorInvitation({
    required String placeId,
    required String targetUid,
  }) async {
    await _functions
        .httpsCallable('revokeNoteAdministratorInvitation')
        .call<Map<String, dynamic>>({
          'placeId': placeId,
          'targetUid': targetUid,
        });
  }

  @override
  Future<void> removeNoteAdministrator({
    required String placeId,
    required String targetUid,
  }) async {
    await _functions
        .httpsCallable('removeNoteAdministrator')
        .call<Map<String, dynamic>>({
          'placeId': placeId,
          'targetUid': targetUid,
        });
  }

  @override
  Future<NoteAdministratorAccess> getNoteAdministratorAccess(
    String placeId,
  ) async {
    final result = await _functions
        .httpsCallable('getNoteAdministratorAccess')
        .call<Map<String, dynamic>>({'placeId': placeId});
    final administrators = result.data['administrators'];
    final pendingInvitations = result.data['pendingInvitations'];
    if (administrators is! List || pendingInvitations is! List) {
      throw const FormatException('Administrator access response is invalid.');
    }
    return NoteAdministratorAccess(
      creatorUid: _requiredString(result.data, 'creatorUid'),
      administrators: administrators
          .map((value) {
            final data = Map<String, dynamic>.from(value as Map);
            return NoteAdministrator(
              userId: _requiredString(data, 'userId'),
              isCreator: data['isCreator'] == true,
              displayName: data['displayName'] as String?,
              photoUrl: data['photoUrl'] as String?,
              invitedByUid: data['invitedByUid'] as String?,
              grantedAt: _optionalDate(data['grantedAtMillis']),
            );
          })
          .toList(growable: false),
      pendingInvitations: pendingInvitations
          .map((value) {
            final data = Map<String, dynamic>.from(value as Map);
            return PendingNoteAdministratorInvitation(
              targetUid: _requiredString(data, 'targetUid'),
              invitedByUid: _requiredString(data, 'invitedByUid'),
              displayName: data['displayName'] as String?,
              photoUrl: data['photoUrl'] as String?,
              revision: data['revision'] as int,
              expiresAt: _requiredDate(data, 'expiresAtMillis'),
              expired: data['expired'] == true,
            );
          })
          .toList(growable: false),
    );
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
            );
          }).toList(),
        );
  }

  @override
  Future<void> recordNoteVisit(String placeId) async {
    if (screenshotMode) return;

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

  String _requiredString(Map<String, dynamic> data, String field) {
    final value = data[field];
    if (value is! String || value.isEmpty) {
      throw FormatException('$field is invalid.');
    }
    return value;
  }

  DateTime _requiredDate(Map<String, dynamic> data, String field) {
    final value = data[field];
    if (value is! int) throw FormatException('$field is invalid.');
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  DateTime? _optionalDate(Object? value) {
    if (value == null) return null;
    if (value is! int) throw const FormatException('Date is invalid.');
    return DateTime.fromMillisecondsSinceEpoch(value);
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
}

class _ArchivedMaintainedNotesCursor {
  final NoteListSort sort;
  final List<PlaceEntity> bufferedPlaces;
  final DocumentSnapshot? lastCreatedDocument;
  final bool hasMoreCreated;

  const _ArchivedMaintainedNotesCursor({
    required this.sort,
    required this.bufferedPlaces,
    required this.lastCreatedDocument,
    required this.hasMoreCreated,
  });
}

List<PlaceEntity> _sortArchivedMaintainedPlaces(
  Iterable<PlaceEntity> places,
  NoteListSort sort,
) {
  final sorted = {for (final place in places) place.id: place}.values.toList();
  final descending = sort == NoteListSort.archivedNewest;
  sorted.sort((a, b) {
    final aTime = a.archivedAt ?? a.createdAt;
    final bTime = b.archivedAt ?? b.createdAt;
    final byTime = descending ? bTime.compareTo(aTime) : aTime.compareTo(bTime);
    if (byTime != 0) return byTime;
    return descending ? b.id.compareTo(a.id) : a.id.compareTo(b.id);
  });
  return sorted;
}
