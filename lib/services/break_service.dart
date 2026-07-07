import 'package:supabase_flutter/supabase_flutter.dart';

class BreakService {
  final _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> requestBreak(
    String sessionId,
    String childId,
  ) async {
    final existing = await _supabase
        .from('break_requests')
        .select()
        .eq('session_id', sessionId)
        .eq('status', 'pending')
        .maybeSingle();
    if (existing != null) return existing;

    final response = await _supabase
        .from('break_requests')
        .insert({
          'session_id': sessionId,
          'child_id': childId,
          'status': 'pending',
        })
        .select()
        .single();
    return response;
  }

  Future<List<Map<String, dynamic>>> getPendingBreaks(String sessionId) async {
    final response = await _supabase
        .from('break_requests')
        .select()
        .eq('session_id', sessionId)
        .eq('status', 'pending')
        .order('created_at');
    return response;
  }

  Future<void> respondToBreak(String breakId, String decision) async {
    await _supabase
        .from('break_requests')
        .update({
          'status': decision,
          'responded_at': DateTime.now().toIso8601String(),
        })
        .eq('id', breakId);
  }
}
