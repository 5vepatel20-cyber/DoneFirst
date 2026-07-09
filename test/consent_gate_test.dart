import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/services/consent_service.dart';

// Tests for the constants and pure-logic parts of the re-consent
// flow. The ConsentGate widget itself can't be tested in isolation
// here because it touches Supabase.instance at construction time
// — covered end-to-end in the manual test plan.

void main() {
  test('typePolicyUpdate is a stable string', () {
    // Stored in DB. If this changes without a migration, every
    // existing audit row becomes unparseable.
    expect(ConsentService.typePolicyUpdate, 'policy_update');
  });

  test('all consent-type constants are unique', () {
    final all = <String>{
      ConsentService.typeAccountCreation,
      ConsentService.typeChildDataCollection,
      ConsentService.typeAiVerification,
      ConsentService.typePolicyUpdate,
    };
    expect(all.length, 4);
  });

  test('currentPolicyVersion looks dated (vN-YYYY-MM-DD)', () {
    final v = ConsentService.currentPolicyVersion;
    expect(v, startsWith('v'));
    expect(v, contains('-'));
    expect(v.split('-').length, greaterThanOrEqualTo(3));
  });

  test('ConsentRecord.displayType returns the policy-update label', () {
    final r = ConsentRecord(
      id: 'x',
      parentId: 'p',
      consentType: ConsentService.typePolicyUpdate,
      consentVersion: 'v2',
      createdAt: DateTime.utc(2026, 8, 1),
    );
    expect(r.displayType, 'Re-consent to updated policy');
  });
}