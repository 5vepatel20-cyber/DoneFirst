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

  /// Approve a pending break. Stamps `started_at = now()` so the
  /// kid app's realtime subscription can compute "am I on a break
  /// right now?" from the latest row. Without started_at the kid
  /// would only see a status flip and would have no way to know
  /// when the break should end — the parent-side BreakTimer is
  /// purely local and isn't visible to the kid.
  Future<void> approveBreak(String requestId) async {
    await _supabase
        .from('break_requests')
        .update({
          'status': 'approved',
          'started_at': DateTime.now().toIso8601String(),
        })
        .eq('id', requestId);
  }

  Future<void> denyBreak(String requestId) async {
    await _supabase
        .from('break_requests')
        .update({'status': 'denied'})
        .eq('id', requestId);
  }

  /// Mark a previously-approved break as completed. Called when
  /// the parent's BreakTimer counts down to zero. Stamps
  /// `ended_at = now()` so the kid app's realtime listener can
  /// transition out of `KidLockState.onBreak` and re-engage the
  /// app block + kiosk lock.
  Future<void> endBreak(String requestId) async {
    await _supabase
        .from('break_requests')
        .update({
          'status': 'completed',
          'ended_at': DateTime.now().toIso8601String(),
        })
        .eq('id', requestId)
        .eq('status', 'approved');
  }

  /// Parent-initiated early end. Treated like a normal completion
  /// on the kid side (re-lock immediately) but tagged as
  /// 'cancelled' so the data-export report distinguishes "break
  /// ran the full 5 min" from "parent cut it short".
  Future<void> cancelBreak(String requestId) async {
    await _supabase
        .from('break_requests')
        .update({
          'status': 'cancelled',
          'ended_at': DateTime.now().toIso8601String(),
        })
        .eq('id', requestId)
        .eq('status', 'approved');
  }
}
