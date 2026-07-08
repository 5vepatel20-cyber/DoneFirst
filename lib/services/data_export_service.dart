import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Builds a portable JSON snapshot of everything we hold about a parent
/// and their family. This is GDPR Article 20 ("right to data
/// portability") in code form: parents can take their data and leave.
///
/// Owner-scoped: every query filters by the current auth.uid() or via
/// the parent's family_id, so an exported snapshot can never contain
/// another family's data.
///
/// Does NOT include:
///   - Proof photo binaries. Signed URLs are 7-day-expiring and not
///     portable. Parents can save individual photos before they expire
///     using the proof viewer.
///   - Internal IDs that don't round-trip (e.g. realtime subscription
///     tokens).
class DataExportService {
  final _supabase = Supabase.instance.client;

  /// Bump when the export schema changes in a non-additive way. UI can
  /// show the version so parents know what they're getting.
  static const String exportVersion = '1.0';

  /// Build the export for the currently signed-in parent. Returns a
  /// Map ready to be JSON-encoded.
  Future<Map<String, dynamic>> buildExport() async {
    final userId = _supabase.auth.currentUser!.id;
    final user = _supabase.auth.currentUser!;

    final parentRow = await _supabase
        .from('parents')
        .select()
        .eq('id', userId)
        .maybeSingle();

    final familyId = parentRow?['family_id'] as String?;
    final familyRow = familyId == null
        ? null
        : await _supabase
            .from('families')
            .select()
            .eq('id', familyId)
            .maybeSingle();

    final childrenRows = familyId == null
        ? const <Map<String, dynamic>>[]
        : await _supabase
            .from('children')
            .select()
            .eq('family_id', familyId);

    final children = <Map<String, dynamic>>[];
    for (final child in childrenRows) {
      final childId = child['id'] as String;
      final sessions = await _buildSessionsForChild(childId);
      final schedules = await _supabase
          .from('recurring_schedules')
          .select()
          .eq('child_id', childId);
      children.add({
        ...child,
        'sessions': sessions,
        'recurring_schedules': schedules,
      });
    }

    final presets = await _supabase
        .from('lock_presets')
        .select()
        .eq('parent_id', userId);

    final notifications = await _supabase
        .from('notifications')
        .select()
        .eq('parent_id', userId);

    // Consent + usage log may not exist yet if migrations 8/9 haven't
    // been run. Swallow errors gracefully so the rest of the export
    // still works.
    final consentRecords = await _trySelect(
      table: 'parental_consent',
      filter: (q) => q.eq('parent_id', userId),
      orderBy: 'created_at',
      ascending: false,
    );

    final usageRows = await _trySelect(
      table: 'mistral_verification_log',
      filter: (q) => q
          .eq('parent_id', userId)
          .gte('called_at',
              DateTime.now().toUtc().subtract(const Duration(days: 30)).toIso8601String()),
    );

    return {
      'exportVersion': exportVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'parent': {
        'id': userId,
        'email': user.email,
        'displayName': parentRow?['display_name'],
        'familyId': familyId,
        'role': parentRow?['role'],
      },
      'family': familyRow,
      'children': children,
      'lock_presets': presets,
      'notifications': notifications,
      'consent_records': consentRecords,
      'usage_stats': {
        'mistral_verifications_last_30_days': usageRows.length,
        'consent_policy_version':
            consentRecords.isNotEmpty ? consentRecords.first['consent_version'] : null,
      },
      'notes': [
        'Proof photo binaries are not included. Use the in-app proof '
            'viewer to save photos before the 7-day signed URL expires.',
        'Account deletion is a separate action — see Settings → '
            'Delete Account.',
      ],
    };
  }

  Future<List<Map<String, dynamic>>> _buildSessionsForChild(
    String childId,
  ) async {
    final sessions = await _supabase
        .from('homework_sessions')
        .select()
        .eq('child_id', childId)
        .order('started_at', ascending: false);

    final out = <Map<String, dynamic>>[];
    for (final session in sessions) {
      final sessionId = session['id'] as String;
      final tasks = await _supabase
          .from('homework_tasks')
          .select()
          .eq('session_id', sessionId);
      final proofs = await _supabase
          .from('proof_submissions')
          .select()
          .eq('session_id', sessionId);
      final breaks = await _supabase
          .from('break_requests')
          .select()
          .eq('session_id', sessionId);
      out.add({
        ...session,
        'tasks': tasks,
        'proofs': proofs,
        'break_requests': breaks,
      });
    }
    return out;
  }

  /// Best-effort query for tables that may not exist yet (migrations
  /// 8/9 not run). Returns [] on any error so the rest of the export
  /// still works.
  Future<List<Map<String, dynamic>>> _trySelect({
    required String table,
    required dynamic Function(dynamic) filter,
    String? orderBy,
    bool ascending = true,
  }) async {
    try {
      dynamic query = _supabase.from(table).select();
      query = filter(query);
      if (orderBy != null) {
        query = query.order(orderBy, ascending: ascending);
      }
      final response = await query;
      return List<Map<String, dynamic>>.from(response);
    } catch (_) {
      return const [];
    }
  }

  /// Convenience: JSON-encoded string with 2-space indent for readability.
  Future<String> exportAsJsonString() async {
    final data = await buildExport();
    return const JsonEncoder.withIndent('  ').convert(data);
  }
}