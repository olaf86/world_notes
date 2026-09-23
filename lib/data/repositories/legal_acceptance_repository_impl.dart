import 'package:cloud_firestore/cloud_firestore.dart';

import '../../config/app_config.dart';
import '../../domain/entities/legal_acceptance.dart';
import '../../domain/repositories/legal_acceptance_repository.dart';
import '../../services/legal_acceptance_store.dart';
import '../../services/world_firebase_clients.dart';

class LegalAcceptanceRepositoryImpl implements LegalAcceptanceRepository {
  const LegalAcceptanceRepositoryImpl({
    required FirebaseFirestore firestore,
    required WorldFunctionsClient functions,
    required LegalAcceptanceStore store,
  }) : _firestore = firestore,
       _functions = functions,
       _store = store;

  final FirebaseFirestore _firestore;
  final WorldFunctionsClient _functions;
  final LegalAcceptanceStore _store;

  @override
  Stream<LegalAcceptance?> watch(String userId) {
    final cached = _store.readCurrent(userId);
    if (cached != null) return Stream.value(cached);

    return _firestore.collection('users').doc(userId).snapshots().asyncMap((
      doc,
    ) async {
      if (!doc.exists) return null;
      final data = doc.data();
      final acceptance = LegalAcceptance(
        serviceTermsVersion: data?['serviceTermsAcceptedVersion'] as String?,
        privacyPolicyVersion:
            data?['privacyPolicyAcknowledgedVersion'] as String?,
      );
      await _store.write(userId, acceptance);
      return acceptance;
    });
  }

  @override
  Future<void> acceptCurrent({
    required String userId,
    required String locale,
  }) async {
    final response = await _functions
        .httpsCallable('acceptServiceTerms')
        .call<Map<String, dynamic>>({
          'serviceTermsVersion': AppConfig.currentServiceTermsVersion,
          'privacyPolicyVersion': AppConfig.currentPrivacyPolicyVersion,
          'locale': locale,
        });
    final data = response.data;
    if (data['serviceTermsVersion'] != AppConfig.currentServiceTermsVersion ||
        data['privacyPolicyVersion'] != AppConfig.currentPrivacyPolicyVersion) {
      throw StateError('The legal acceptance response is invalid.');
    }
    await _store.writeCurrent(userId);
  }
}
