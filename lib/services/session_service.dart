import 'package:supabase_flutter/supabase_flutter.dart';

class SessionService {
  final _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> startSession({
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
    return response;
  }

  Future<List<Map<String, dynamic>>> getActiveSession(String childId) async {
    final response = await _supabase
        .from('homework_sessions')
        .select()
        .eq('child_id', childId)
        .eq('status', 'active')
        .order('started_at', ascending: false)
        .limit(1);
    return response;
  }

  Future<Map<String, dynamic>?> getSessionById(String sessionId) async {
    final response = await _supabase
        .from('homework_sessions')
        .select()
        .eq('id', sessionId)
        .maybeSingle();
    return response;
  }

  Future<List<Map<String, dynamic>>> getHistory(String childId) async {
    final response = await _supabase
        .from('homework_sessions')
        .select()
        .eq('child_id', childId)
        .order('started_at', ascending: false);
    return response;
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

  Future<List<Map<String, dynamic>>> getChildren(String parentId) async {
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
    return children;
  }

  Future<Map<String, dynamic>> addChild(String name, String familyId) async {
    final response = await _supabase
        .from('children')
        .insert({'family_id': familyId, 'name': name})
        .select()
        .single();
    return response;
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

  Future<String> getOrCreateFamily() async {
    final parent = await _supabase
        .from('parents')
        .select('family_id')
        .eq('id', _supabase.auth.currentUser!.id)
        .single();
    if (parent['family_id'] != null) {
      return parent['family_id'];
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
    return family['id'];
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

  Future<int> getMonthlySessionCount(String parentId) async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1).toIso8601String();
    final response = await _supabase
        .from('homework_sessions')
        .select('id')
        .eq('parent_id', parentId)
        .gte('started_at', startOfMonth);
    return response.length;
  }
}
