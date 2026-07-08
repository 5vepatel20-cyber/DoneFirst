import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class SessionService {
  final _supabase = Supabase.instance.client;

  Future<HomeworkSession> startSession({
    required String childId,
    required int minLockMinutes,
    required int maxLiftMinutes,
    required String approvalMode,
  }) async {
    final response = await _supabase
        .from('homework_sessions')
        .insert({
          'child_id': childId,
          'parent_id': _supabase.auth.currentUser!.id,
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
    parentId ??= _supabase.auth.currentUser!.id;
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
    final response = await _supabase
        .from('children')
        .insert({
          'family_id': familyId,
          'name': name,
          'parent_id': _supabase.auth.currentUser!.id,
          if (color != null) 'color': color,
          if (emoji != null) 'emoji': emoji,
        })
        .select()
        .single();
    return Child.fromMap(response);
  }

  Future<void> deleteChild(String childId) async {
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
          if (color != null) 'color': color,
          if (emoji != null) 'emoji': emoji,
        })
        .eq('id', childId);
  }

  Future<String> getOrCreateFamily() async {
    final parent = await _supabase
        .from('parents')
        .select('family_id')
        .eq('id', _supabase.auth.currentUser!.id)
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
        .eq('id', _supabase.auth.currentUser!.id);
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
    final uid = parentId ?? _supabase.auth.currentUser!.id;
    final response = await _supabase
        .from('homework_sessions')
        .select('id')
        .eq('parent_id', uid)
        .gte('started_at', startOfMonth);
    return response.length;
  }

  Future<Map<String, int>> getFamilyStats() async {
    final sessions = await _supabase
        .from('homework_sessions')
        .select('status, min_lock_minutes')
        .eq('parent_id', _supabase.auth.currentUser!.id);
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
