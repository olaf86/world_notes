import '../entities/legal_acceptance.dart';

abstract interface class LegalAcceptanceRepository {
  Stream<LegalAcceptance?> watch(String userId);

  Future<void> acceptCurrent({required String locale});
}
