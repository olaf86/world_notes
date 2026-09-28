import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/services/legal_consent_diagnostics_service.dart';

void main() {
  test('keeps only bounded non-personal callable failure fields', () {
    final information = buildLegalConsentFailureInformation(
      code: 'failed-precondition',
      message: 'World is still preparing.\nTry again.',
      details: {
        'reason': 'world-not-ready',
        'worldId': 'asia',
        'homeWorld': 'asia',
        'email': 'developer@example.com',
        'submittedText': 'private input',
      },
    );

    expect(
      information,
      containsAll(<String>[
        'functionsCode=failed-precondition',
        'functionsMessage=World is still preparing. Try again.',
        'reason=world-not-ready',
        'worldId=asia',
        'homeWorld=asia',
        'detailsOmitted=2',
      ]),
    );
    expect(information.join(' '), isNot(contains('developer@example.com')));
    expect(information.join(' '), isNot(contains('private input')));
  });

  test('omits unsupported detail shapes and bounds text fields', () {
    final information = buildLegalConsentFailureInformation(
      code: 'x' * 100,
      message: 'm' * 300,
      details: const ['not', 'a', 'map'],
    );

    expect(information[0], 'functionsCode=${'x' * 64}');
    expect(information[1], 'functionsMessage=${'m' * 240}');
    expect(information, contains('detailsOmitted=1'));
  });
}
