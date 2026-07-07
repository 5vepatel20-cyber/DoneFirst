import 'package:supabase_flutter/supabase_flutter.dart';

class CoparentService {
  final _supabase = Supabase.instance.client;

  Future<void> invite({required String familyId, required String email}) async {
    await _supabase.from('parent_invites').insert({
      'family_id': familyId,
      'inviter_id': _supabase.auth.currentUser!.id,
      'invitee_email': email,
      'status': 'pending',
    });
  }

  Future<List<Map<String, dynamic>>> getPendingInvites(String familyId) async {
    final response = await _supabase
        .from('parent_invites')
        .select()
        .eq('family_id', familyId)
        .eq('status', 'pending')
        .order('created_at');
    return response;
  }

  Future<List<Map<String, dynamic>>> getCoParents(String familyId) async {
    final response = await _supabase
        .from('parents')
        .select('id, email, display_name, role')
        .eq('family_id', familyId)
        .neq('id', _supabase.auth.currentUser!.id);
    return response;
  }

  Future<void> cancelInvite(String inviteId) async {
    await _supabase
        .from('parent_invites')
        .update({'status': 'cancelled'})
        .eq('id', inviteId);
  }

  Future<void> acceptInvite(String inviteId) async {
    final invite = await _supabase
        .from('parent_invites')
        .select()
        .eq('id', inviteId)
        .single();
    final familyId = invite['family_id'];

    await _supabase
        .from('parents')
        .update({'family_id': familyId})
        .eq('id', _supabase.auth.currentUser!.id);

    await _supabase
        .from('parent_invites')
        .update({'status': 'accepted'})
        .eq('id', inviteId);
  }

  Future<List<Map<String, dynamic>>> getMyInvites() async {
    final email = _supabase.auth.currentUser!.email;
    if (email == null) return [];
    final response = await _supabase
        .from('parent_invites')
        .select('id, family_id, inviter_id, status')
        .eq('invitee_email', email)
        .eq('status', 'pending');
    return response;
  }
}
