import 'package:supabase_flutter/supabase_flutter.dart';

/// Audit-trail service for parental-consent records.
///
/// COPPA / GDPR-K require verifiable parental consent before collecting
/// personal data from children. This service persists an immutable
/// record of every consent capture (signup, child-add, policy-version
/// bump) so we can produce an audit trail on demand.
///
/// Insert-only on the client side — RLS prevents UPDATE / DELETE so
/// consent records cannot be silently back-dated or removed.
class ConsentService {
  final _supabase = Supabase.instance.client;

  /// The version string of the policy the parent is consenting to.
  /// Bump this when PRIVACY.md or TERMS.md changes substantively; the
  /// app can then prompt existing users to re-consent.
  static const String currentPolicyVersion = 'v1-2026-07-08';

  /// Types of consent we capture. Stored as TEXT in `parental_consent.consent_type`.
  static const String typeAccountCreation = 'account_creation';
  static const String typeChildDataCollection = 'child_data_collection';
  static const String typeAiVerification = 'ai_verification';

  /// Record a consent event. The RLS policy enforces `parent_id = auth.uid()`,
  /// so a client can only insert consent on its own behalf.
  Future<void> recordConsent({
    required String parentId,
    required String consentType,
    String policyVersion = currentPolicyVersion,
    String? policyUrl,
  }) async {
    await _supabase.from('parental_consent').insert({
      'parent_id': parentId,
      'consent_type': consentType,
      'consent_version': policyVersion,
      'policy_url': policyUrl,
    });
  }

  /// All consent records for a parent, newest first.
  Future<List<ConsentRecord>> getConsentHistory(String parentId) async {
    final response = await _supabase
        .from('parental_consent')
        .select()
        .eq('parent_id', parentId)
        .order('created_at', ascending: false);
    return (response as List)
        .cast<Map<String, dynamic>>()
        .map(ConsentRecord.fromMap)
        .toList();
  }
}

class ConsentRecord {
  final String id;
  final String parentId;
  final String consentType;
  final String consentVersion;
  final String? policyUrl;
  final DateTime createdAt;

  const ConsentRecord({
    required this.id,
    required this.parentId,
    required this.consentType,
    required this.consentVersion,
    required this.createdAt,
    this.policyUrl,
  });

  factory ConsentRecord.fromMap(Map<String, dynamic> map) => ConsentRecord(
        id: map['id'] as String,
        parentId: map['parent_id'] as String,
        consentType: map['consent_type'] as String,
        consentVersion: map['consent_version'] as String,
        policyUrl: map['policy_url'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  /// Human-readable label for the consent type. Used in the settings UI.
  String get displayType {
    switch (consentType) {
      case ConsentService.typeAccountCreation:
        return 'Account creation (COPPA attestation)';
      case ConsentService.typeChildDataCollection:
        return 'Collection of child data';
      case ConsentService.typeAiVerification:
        return 'AI proof verification via Mistral';
      default:
        return consentType;
    }
  }
}