import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'consent_service.dart';

class SessionService {
  final _supabase = Supabase.instance.client;

  String? get _userId => _supabase.auth.currentUser?.id;

  Future<HomeworkSession> startSession({
    required String childId,
    required int minLockMinutes,
    required int maxLiftMinutes,
    required String approvalMode,
  }) async {
    final parentId = _userId;
    if (parentId == null) throw StateError('No authenticated user');
    final response = await _supabase
        .from('homework_sessions')
        .insert({
          'child_id': childId,
          'parent_id': parentId,
          'status': 'active',
          'min_lock_minutes': minLockMinutes,
          'max_lift_minutes': maxLiftMinutes,
          'approval_mode': approvalMode,
        })
        .select()
        .single();
    return HomeworkSession.fromMap(response);
  }

  Future<List<HomeworkSession>> getActiveSessions() async {
    final response = await _supabase
        .from('homework_sessions')
        .select()
        .eq('status', 'active')
        .order('started_at', ascending: false);
    return response.map((m) => HomeworkSession.fromMap(m)).toList();
  }

  Future<HomeworkSession?> getActiveSession(String childId) async {
    final response = await _supabase
        .from('homework_sessions')
        .select()
        .eq('child_id', childId)
        .eq('status', 'active')
        .order('started_at', ascending: false)
        .limit(1);
    if (response.isEmpty) return null;
    return HomeworkSession.fromMap(response.first);
  }

  Future<HomeworkSession?> getSessionById(String sessionId) async {
    final response = await _supabase
        .from('homework_sessions')
        .select()
        .eq('id', sessionId)
        .maybeSingle();
    if (response == null) return null;
    return HomeworkSession.fromMap(response);
  }

  Future<List<HomeworkSession>> getHistory(String childId) async {
    final response = await _supabase
        .from('homework_sessions')
        .select()
        .eq('child_id', childId)
        .order('started_at', ascending: false);
    return response.map((m) => HomeworkSession.fromMap(m)).toList();
  }

  Future<void> endSession(String sessionId) async {
    await _supabase
        .from('homework_sessions')
        .update({
          'status': 'completed',
          'ended_at': DateTime.now().toIso8601String(),
        })
        .eq('id', sessionId);
  }

  Future<void> cancelSession(String sessionId) async {
    await _supabase
        .from('homework_sessions')
        .update({'status': 'cancelled'})
        .eq('id', sessionId);
  }

  Future<void> pauseSession(String sessionId) async {
    await _supabase
        .from('homework_sessions')
        .update({'status': 'paused'})
        .eq('id', sessionId);
  }

  Future<void> resumeSession(String sessionId) async {
    await _supabase
        .from('homework_sessions')
        .update({'status': 'active'})
        .eq('id', sessionId);
  }

  Future<List<Child>> getChildren([String? parentId]) async {
    parentId ??= _userId;
    if (parentId == null) return [];
    final family = await _supabase
        .from('parents')
        .select('family_id')
        .eq('id', parentId)
        .single();
    if (family['family_id'] == null) return [];
    final children = await _supabase
        .from('children')
        .select()
        .eq('family_id', family['family_id']);
    return children.map((m) => Child.fromMap(m)).toList();
  }

  Future<Child> addChild(String name, String familyId,
      {String? color, String? emoji}) async {
    final parentId = _userId;
    if (parentId == null) throw StateError('No authenticated user');
    // COPPA / GDPR-K: every time the parent enrolls a child in our
    // service, that's a fresh consent act for that minor's data.
    // Record it as an immutable audit row. Non-fatal if the audit
    // table isn't installed yet (migration 9 not run) — the child
    // record is what we need to make the app work.
    //
    // The children insert and the consent audit row are independent
    // writes (different tables, no shared keys), so we kick them off
    // in parallel and wrap the consent future in a catchError so a
    // transient DB hiccup there doesn't fail the whole addChild.
    final consentFut = ConsentService()
        .recordConsent(
          parentId: parentId,
          consentType: ConsentService.typeChildDataCollection,
        )
        .catchError((Object _) {
      // swallow — comment above
      return null;
    });
    final insertFut = _supabase
        .from('children')
        .insert({
          'family_id': familyId,
          'name': name,
          'parent_id': parentId,
          'color': ?color,
          'emoji': ?emoji,
        })
        .select()
        .single();
    final response = await insertFut;
    await consentFut;
    return Child.fromMap(response);
  }

  Future<void> deleteChild(String childId) async {
    // Delete the child's rows in FK dependency order.
    //
    // The main hazard is trigger-induced FK violations:
    //   DELETE children
    //     → CASCADE deletes device_pairings
    //       → trg_code_cancelled fires → INSERT kid_device_events
    //         → FK on child_id fails (children row is gone)
    //
    // Solution: delete device_pairings and kid_device_events for
    // this child BEFORE touching children, so triggers fire while
    // the child row still exists. Similarly, delete homework data
    // before children to avoid homework_sessions FK violations.

    // 1) Audit log + pairing codes — delete before children so
    //    triggers fire while the child row still exists.
    await _supabase
        .from('kid_device_events')
        .delete()
        .eq('child_id', childId);
    await _supabase
        .from('device_pairings')
        .delete()
        .eq('child_id', childId);

    // 2) Homework data in FK dependency order.
    final sessions = await _supabase
        .from('homework_sessions')
        .select('id')
        .eq('child_id', childId);
    final sessionIds =
        (sessions as List).map((r) => r['id'] as String).toList();

    for (final sid in sessionIds) {
      final tasks = await _supabase
          .from('homework_tasks')
          .select('id')
          .eq('session_id', sid);
      final taskIds =
          (tasks as List).map((r) => r['id'] as String).toList();

      if (taskIds.isNotEmpty) {
        await _supabase
            .from('proof_submissions')
            .delete()
            .inFilter('task_id', taskIds);
        await _supabase
            .from('homework_tasks')
            .delete()
            .inFilter('id', taskIds);
      }

      await _supabase.from('break_requests').delete().eq('session_id', sid);
    }

    if (sessionIds.isNotEmpty) {
      await _supabase
          .from('homework_sessions')
          .delete()
          .eq('child_id', childId);
    }

    // 3) Now safe to delete the child — CASCADE handles kid_devices,
    //    but device_pairings (which also CASCADE-references children)
    //    is already gone, so no trigger-induced FK violations.
    await _supabase.from('children').delete().eq('id', childId);
  }

  Future<void> renameChild(String childId, String newName) async {
    await _supabase
        .from('children')
        .update({'name': newName})
        .eq('id', childId);
  }

  Future<void> updateChildProfile(
      String childId, {String? color, String? emoji}) async {
    await _supabase
        .from('children')
        .update({
          'color': ?color,
          'emoji': ?emoji,
        })
        .eq('id', childId);
  }

  Future<String> getOrCreateFamily() async {
    final parentId = _userId;
    if (parentId == null) throw StateError('No authenticated user');
    final parent = await _supabase
        .from('parents')
        .select('family_id')
        .eq('id', parentId)
        .single();
    if (parent['family_id'] != null) {
      return parent['family_id'] as String;
    }
    final family = await _supabase
        .from('families')
        .insert({'name': 'My Family'})
        .select()
        .single();
    await _supabase
        .from('parents')
        .update({'family_id': family['id']})
        .eq('id', parentId);
    return family['id'] as String;
  }

  Future<void> ensureParentRecord(
    String userId,
    String email,
    String displayName,
  ) async {
    final existing = await _supabase
        .from('parents')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (existing == null) {
      await _supabase.from('parents').insert({
        'id': userId,
        'email': email,
        'display_name': displayName,
      });
    }
  }

  Future<void> extendSession(String sessionId, int extraMinutes) async {
    final session = await _supabase
        .from('homework_sessions')
        .select('min_lock_minutes, max_lift_minutes')
        .eq('id', sessionId)
        .single();
    final currentMin = session['min_lock_minutes'] as int? ?? 60;
    final currentMax = session['max_lift_minutes'] as int? ?? currentMin;
    await _supabase
        .from('homework_sessions')
        .update({
          'min_lock_minutes': currentMin + extraMinutes,
          'max_lift_minutes': currentMax + extraMinutes,
        })
        .eq('id', sessionId);
  }

  Future<int> getMonthlySessionCount([String? parentId]) async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1).toIso8601String();
    final uid = parentId ?? _userId;
    if (uid == null) return 0;
    final response = await _supabase
        .from('homework_sessions')
        .select('id')
        .eq('parent_id', uid)
        .gte('started_at', startOfMonth);
    return response.length;
  }

  Future<Map<String, int>> getFamilyStats() async {
    final parentId = _userId;
    if (parentId == null) return {'sessions': 0, 'minutes': 0, 'approved': 0};
    final sessions = await _supabase
        .from('homework_sessions')
        .select('status, min_lock_minutes')
        .eq('parent_id', parentId);
    int totalSessions = sessions.length;
    int totalMinutes = 0;
    int approved = 0;
    for (final s in sessions) {
      totalMinutes += (s['min_lock_minutes'] as int? ?? 0);
      if (s['status'] == 'completed') approved++;
    }
    return {
      'sessions': totalSessions,
      'minutes': totalMinutes,
      'approved': approved,
    };
  }
}
