import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final _supabase = Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;

  Future<void> resendVerification() async {
    await _supabase.auth.resend(
      type: OtpType.signup,
      email: _supabase.auth.currentUser!.email!,
    );
  }

  Future<User?> signUp(
    String email,
    String password,
    String displayName,
  ) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {'display_name': displayName},
    );
    return response.user;
  }

  Future<User?> signIn(String email, String password) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return response.user;
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  Future<void> changePassword(String newPassword) async {
    await _supabase.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> deleteAccount() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final parent = await _supabase
        .from('parents')
        .select('family_id')
        .eq('id', user.id)
        .maybeSingle();
    final familyId = parent?['family_id'] as String?;

    if (familyId != null) {
      final children = await _supabase
          .from('children')
          .select('id')
          .eq('family_id', familyId);
      for (final c in children) {
        final childId = c['id'] as String;
        final sessions = await _supabase
            .from('homework_sessions')
            .select('id')
            .eq('child_id', childId);
        for (final s in sessions) {
          final sessionId = s['id'] as String;
          await _supabase
              .from('proof_submissions')
              .delete()
              .eq('session_id', sessionId);
          await _supabase
              .from('homework_tasks')
              .delete()
              .eq('session_id', sessionId);
          await _supabase
              .from('break_requests')
              .delete()
              .eq('session_id', sessionId);
        }
        await _supabase
            .from('homework_sessions')
            .delete()
            .eq('child_id', childId);
      }
      await _supabase.from('children').delete().eq('family_id', familyId);
      await _supabase.from('notifications').delete().eq('parent_id', user.id);
      await _supabase.from('lock_presets').delete().eq('parent_id', user.id);
      await _supabase.from('recurring_schedules').delete().eq('parent_id', user.id);
      await _supabase.from('parent_invites').delete().eq('inviter_id', user.id);
      await _supabase.from('families').delete().eq('id', familyId);
    }

    await _supabase.from('parents').delete().eq('id', user.id);
    await _supabase.auth.admin.deleteUser(user.id);
    await _supabase.auth.signOut();
  }
}
