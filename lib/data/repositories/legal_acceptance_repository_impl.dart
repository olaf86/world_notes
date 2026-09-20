import 'package:cloud_firestore/cloud_firestore.dart';

import '../../config/app_config.dart';
import '../../domain/entities/legal_acceptance.dart';
import '../../domain/repositories/legal_acceptance_repository.dart';
import '../../services/world_firebase_clients.dart';

class LegalAcceptanceRepositoryImpl implements LegalAcceptanceRepository {
  const LegalAcceptanceRepositoryImpl({
    required FirebaseFirestore firestore,
    required WorldFunctionsClient functions,
  }) : _firestore = firestore,
       _functions = functions;

  final FirebaseFirestore _firestore;
  final WorldFunctionsClient _functions;

  @override
  Stream<LegalAcceptance?> watch(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      final data = doc.data();
      return LegalAcceptance(
        serviceTermsVersion: data?['serviceTermsAcceptedVersion'] as String?,
        privacyPolicyVersion:
            data?['privacyPolicyAcknowledgedVersion'] as String?,
      );
    });
  }

  @override
  Future<void> acceptCurrent({required String locale}) async {
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
  }
}
