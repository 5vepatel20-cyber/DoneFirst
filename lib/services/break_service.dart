import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class BreakService {
  final _supabase = Supabase.instance.client;

  Future<BreakRequest> requestBreak(String sessionId, String childId) async {
    final response = await _supabase
        .from('break_requests')
        .insert({
          'session_id': sessionId,
          'child_id': childId,
          'status': 'pending',
        })
        .select()
        .single();
    return BreakRequest.fromMap(response);
  }

  Future<List<BreakRequest>> getPendingRequests(String childId) async {
    final response = await _supabase
        .from('break_requests')
        .select()
        .eq('child_id', childId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return response.map((m) => BreakRequest.fromMap(m)).toList();
  }

  /// Most-recent break request for a session regardless of status.
  /// Used by the kid-side home screen to keep its "Ask for a break"
  /// button in sync with server state — without this, the button
  /// would stay stuck in "Requested" mode after the parent approved
  /// or denied the request, until the kid pulled to refresh or
  /// restarted the app.
  Future<BreakRequest?> getLatestForSession(String sessionId) async {
    final response = await _supabase
        .from('break_requests')
        .select()
        .eq('session_id', sessionId)
        .order('created_at', ascending: false)
        .limit(1);
    if (response.isEmpty) return null;
    return BreakRequest.fromMap(response.first);
  }

  Future<List<BreakRequest>> getPendingBreaks(String sessionId) async {
    final response = await _supabase
        .from('break_requests')
        .select()
        .eq('session_id', sessionId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return response.map((m) => BreakRequest.fromMap(m)).toList();
  }

  Future<void> respondToBreak(String requestId, String decision) async {
    if (decision == 'approved') {
      await approveBreak(requestId);
    } else {
      await denyBreak(requestId);
    }
  }

  Future<void> approveBreak(String requestId) async {
    await _supabase
        .from('break_requests')
        .update({'status': 'approved'})
        .eq('id', requestId);
  }

  Future<void> denyBreak(String requestId) async {
    await _supabase
        .from('break_requests')
        .update({'status': 'denied'})
        .eq('id', requestId);
  }
}
