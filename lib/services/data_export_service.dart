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

    // All the family-level reads are independent — fan out and join.
    final familyResults = await Future.wait([
      Future.value(familyId),
      familyId == null
          ? Future.value(null)
          : _supabase.from('families').select().eq('id', familyId).maybeSingle(),
      familyId == null
          ? Future.value(<Map<String, dynamic>>[])
          : _supabase.from('children').select().eq('family_id', familyId),
    ]);
    final familyRow = familyResults[1] as Map<String, dynamic>?;
    final childrenRows = familyResults[2] as List<Map<String, dynamic>>;

    // Per-child work (sessions + recurring_schedules) is independent
    // across children, so fire in parallel.
    final children = await Future.wait(childrenRows.map((child) async {
      final childId = child['id'] as String;
      final results = await Future.wait([
        _buildSessionsForChild(childId),
        _supabase
            .from('recurring_schedules')
            .select()
            .eq('child_id', childId),
      ]);
      return {
        ...child,
        'sessions': results[0],
        'recurring_schedules': results[1],
      };
    }));

    // All remaining parent-level reads are independent.
    final tailResults = await Future.wait([
      _supabase.from('lock_presets').select().eq('parent_id', userId),
      _supabase.from('notifications').select().eq('parent_id', userId),
      // Consent + usage log may not exist yet if migrations 8/9
      // haven't been run. Swallow errors gracefully so the rest of
      // the export still works.
      _trySelect(
        table: 'parental_consent',
        filter: (q) => q.eq('parent_id', userId),
        orderBy: 'created_at',
        ascending: false,
      ),
      _trySelect(
        table: 'mistral_verification_log',
        filter: (q) => q
            .eq('parent_id', userId)
            .gte('called_at', DateTime.now()
                .toUtc()
                .subtract(const Duration(days: 30))
                .toIso8601String()),
      ),
    ]);
    final presets = tailResults[0];
    final notifications = tailResults[1];
    final consentRecords = tailResults[2];
    final usageRows = tailResults[3];

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

    if (sessions.isEmpty) return const [];

    // Previously: 3 sequential awaits per session (tasks, proofs,
    // break_requests). For a kid with N sessions that's 3N round-trips
    // on top of the initial sessions query. Now: one batched query
    // per child-side table, grouped by session_id client-side.
    final sessionIds = sessions
        .map((s) => s['id'] as String)
        .toList(growable: false);

    final childData = await Future.wait([
      _supabase
          .from('homework_tasks')
          .select()
          .inFilter('session_id', sessionIds),
      _supabase
          .from('proof_submissions')
          .select()
          .inFilter('session_id', sessionIds),
      _supabase
          .from('break_requests')
          .select()
          .inFilter('session_id', sessionIds),
    ]);
    final tasksBySession = _groupBySessionId(childData[0]);
    final proofsBySession = _groupBySessionId(childData[1]);
    final breaksBySession = _groupBySessionId(childData[2]);

    return sessions.map((session) {
      final sid = session['id'] as String;
      return {
        ...session,
        'tasks': tasksBySession[sid] ?? const <Map<String, dynamic>>[],
        'proofs': proofsBySession[sid] ?? const <Map<String, dynamic>>[],
        'break_requests': breaksBySession[sid] ?? const <Map<String, dynamic>>[],
      };
    }).toList();
  }

  /// Groups rows that have a `session_id` field by that field.
  /// Used by _buildSessionsForChild to attach child-side rows
  /// (tasks / proofs / break_requests) to their owning session
  /// after a single batched inFilter query.
  Map<String, List<Map<String, dynamic>>> _groupBySessionId(
    List<Map<String, dynamic>> rows,
  ) {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final sid = row['session_id'] as String?;
      if (sid == null) continue;
      out.putIfAbsent(sid, () => []).add(row);
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