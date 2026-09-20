/// The legal documents acknowledged by one account.
class LegalAcceptance {
  const LegalAcceptance({
    required this.serviceTermsVersion,
    required this.privacyPolicyVersion,
  });

  final String? serviceTermsVersion;
  final String? privacyPolicyVersion;

  bool matches({
    required String serviceTermsVersion,
    required String privacyPolicyVersion,
  }) =>
      this.serviceTermsVersion == serviceTermsVersion &&
      this.privacyPolicyVersion == privacyPolicyVersion;
}
