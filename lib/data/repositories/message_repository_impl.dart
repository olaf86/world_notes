import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../../config/app_config.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/message_repository.dart';
import '../models/message_model.dart';

class MessageRepositoryImpl implements MessageRepository {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final _uuid = const Uuid();

  MessageRepositoryImpl({
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
  })  : _firestore = firestore,
        _storage = storage;

  CollectionReference get _messages => _firestore.collection('messages');

  @override
  Stream<List<MessageEntity>> watchMessages(String noteId) {
    return _messages
        .where('noteId', isEqualTo: noteId)
        .orderBy('createdAt', descending: true)
        .limit(AppConfig.messagesPageSize)
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => MessageModel.fromFirestore(doc).toEntity()).toList());
  }

  @override
  Future<List<MessageEntity>> getOlderMessages({
    required String noteId,
    required String beforeMessageId,
    required int limit,
  }) async {
    final pivotDoc = await _messages.doc(beforeMessageId).get();
    if (!pivotDoc.exists) return [];

    final snap = await _messages
        .where('noteId', isEqualTo: noteId)
        .orderBy('createdAt', descending: true)
        .startAfterDocument(pivotDoc)
        .limit(limit)
        .get();

    return snap.docs
        .map((doc) => MessageModel.fromFirestore(doc).toEntity())
        .toList();
  }

  Future<String?> _uploadImage({
    required List<int> bytes,
    required String name,
    required String userId,
  }) async {
    final ext = name.contains('.') ? name.split('.').last : 'jpg';
    final ref = _storage
        .ref()
        .child('messages/$userId/${_uuid.v4()}.$ext');
    await ref.putData(
      Uint8List.fromList(bytes),
      SettableMetadata(contentType: 'image/$ext'),
    );
    return ref.getDownloadURL();
  }

  @override
  Future<MessageEntity> sendMessage({
    required String noteId,
    required String content,
    required String userId,
    required String userName,
    String? userPhotoUrl,
    List<int>? imageBytes,
    String? imageName,
  }) async {
    String? imageUrl;
    if (imageBytes != null && imageName != null) {
      imageUrl = await _uploadImage(
        bytes: imageBytes,
        name: imageName,
        userId: userId,
      );
    }

    final id = _uuid.v4();
    final model = MessageModel(
      id: id,
      noteId: noteId,
      userId: userId,
      userName: userName,
      userPhotoUrl: userPhotoUrl,
      content: content,
      imageUrl: imageUrl,
      createdAt: DateTime.now(),
    );

    await _messages.doc(id).set(model.toFirestore());

    // Increment message count directly on the note document.
    await _firestore
        .collection('notes')
        .doc(noteId)
        .update({'messageCount': FieldValue.increment(1)});

    return model.toEntity();
  }
}
