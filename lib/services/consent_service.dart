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
  static const String typePolicyUpdate = 'policy_update';

  /// True if the most recent consent record for this parent was
  /// captured at an older policy version than the current one.
  /// Used to prompt existing users to re-consent after a policy
  /// version bump.
  ///
  /// Returns false (no re-consent needed) when:
  ///   - The user has no consent records yet (new signup — they
  ///     consented at signup time at the current version)
  ///   - The latest consent version matches the current version
  Future<bool> needsReConsent(String parentId) async {
    final history = await getConsentHistory(parentId);
    if (history.isEmpty) return false;
    return history.first.consentVersion != currentPolicyVersion;
  }

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

  /// Record a full parental-consent capture. Use this when the parent
  /// goes through the multi-checkbox signup flow — it persists their
  /// typed signature plus the per-item acknowledgments, which is what
  /// a regulator would ask for in a COPPA audit.
  ///
  /// [acknowledgments] is a free-form map so the UI can present
  /// whatever set of items matches the current policy version
  /// without having to update the service. We recommend keys like
  /// 'is_adult', 'is_guardian', 'consents_child_data',
  /// 'consents_ai_verification', 'consents_blocking'.
  Future<void> recordParentalConsent({
    required String parentId,
    required String signedName,
    required Map<String, bool> acknowledgments,
    String? childName,
    String consentType = typeAccountCreation,
    String policyVersion = currentPolicyVersion,
  }) async {
    // Filter to only the items the parent actually accepted. We
    // refuse to write a record with no acknowledgments — that would
    // mean the consent flow was bypassed, which is the very thing
    // we're trying to prevent.
    final accepted = <String, bool>{
      for (final entry in acknowledgments.entries)
        if (entry.value) entry.key: true,
    };
    if (accepted.isEmpty) {
      throw ArgumentError(
        'Refusing to record consent with no acknowledgments.',
      );
    }
    if (signedName.trim().isEmpty) {
      throw ArgumentError('Signed name is required.');
    }
    await _supabase.from('parental_consent').insert({
      'parent_id': parentId,
      'consent_type': consentType,
      'consent_version': policyVersion,
      'signed_name': signedName.trim(),
      'acknowledgments': accepted,
      if (childName != null && childName.trim().isNotEmpty)
        'child_name': childName.trim(),
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
      case ConsentService.typePolicyUpdate:
        return 'Re-consent to updated policy';
      default:
        return consentType;
    }
  }
}