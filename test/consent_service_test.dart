import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/services/consent_service.dart';

void main() {
  group('ConsentService constants', () {
    test('currentPolicyVersion is non-empty and follows expected format', () {
      expect(ConsentService.currentPolicyVersion, isNotEmpty);
      // Format: "v1-YYYY-MM-DD" — sanity check it has a dash and looks dated.
      expect(ConsentService.currentPolicyVersion, contains('-'));
      expect(ConsentService.currentPolicyVersion, startsWith('v'));
    });

    test('consent-type constants are stable strings', () {
      // These get stored in the DB and must not change without a
      // migration. This test guards against accidental drift.
      expect(ConsentService.typeAccountCreation, 'account_creation');
      expect(
        ConsentService.typeChildDataCollection,
        'child_data_collection',
      );
      expect(ConsentService.typeAiVerification, 'ai_verification');
    });
  });

  group('ConsentRecord', () {
    test('fromMap round-trips the known fields', () {
      final createdAt = DateTime.utc(2026, 7, 8, 12, 30);
      final map = <String, dynamic>{
        'id': 'id-1',
        'parent_id': 'parent-1',
        'consent_type': ConsentService.typeAccountCreation,
        'consent_version': 'v1-2026-07-08',
        'policy_url': null,
        'created_at': createdAt.toIso8601String(),
      };
      final record = ConsentRecord.fromMap(map);
      expect(record.id, 'id-1');
      expect(record.parentId, 'parent-1');
      expect(record.consentType, ConsentService.typeAccountCreation);
      expect(record.consentVersion, 'v1-2026-07-08');
      expect(record.policyUrl, isNull);
      expect(record.createdAt, createdAt);
    });

    test('displayType returns human-readable label for known types', () {
      ConsentRecord make(String type) => ConsentRecord(
            id: 'id',
            parentId: 'parent',
            consentType: type,
            consentVersion: 'v1',
            createdAt: DateTime.utc(2026, 7, 8),
          );

      expect(
        make(ConsentService.typeAccountCreation).displayType,
        'Account creation (COPPA attestation)',
      );
      expect(
        make(ConsentService.typeChildDataCollection).displayType,
        'Collection of child data',
      );
      expect(
        make(ConsentService.typeAiVerification).displayType,
        'AI proof verification via Mistral',
      );
      // Unknown type falls back to the raw value.
      expect(make('weird_unknown_type').displayType, 'weird_unknown_type');
    });

    test('fromMap with non-UTC createdAt parses correctly', () {
      final map = <String, dynamic>{
        'id': 'id',
        'parent_id': 'p',
        'consent_type': 'x',
        'consent_version': 'v1',
        'policy_url': null,
        'created_at': '2026-07-08T08:00:00.000Z',
      };
      final r = ConsentRecord.fromMap(map);
      expect(r.createdAt.isUtc, isTrue);
    });
  });
}