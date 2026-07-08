import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class CoparentService {
  final _supabase = Supabase.instance.client;

  Future<ParentInvite> inviteCoparent(String email) async {
    final profile = await _supabase
        .from('parents')
        .select('family_id')
        .eq('id', _supabase.auth.currentUser!.id)
        .single();
    final familyId = profile['family_id'] as String?;
    if (familyId == null) throw Exception('No family found');
    final response = await _supabase
        .from('parent_invites')
        .insert({
          'family_id': familyId,
          'inviter_id': _supabase.auth.currentUser!.id,
          'invitee_email': email,
          'status': 'pending',
        })
        .select()
        .single();
    return ParentInvite.fromMap(response);
  }

  Future<List<ParentInvite>> getSentInvites() async {
    final response = await _supabase
        .from('parent_invites')
        .select()
        .eq('inviter_id', _supabase.auth.currentUser!.id)
        .order('created_at', ascending: false);
    return response.map((m) => ParentInvite.fromMap(m)).toList();
  }

  Future<void> revokeInvite(String inviteId) async {
    await _supabase
        .from('parent_invites')
        .update({'status': 'declined'})
        .eq('id', inviteId);
  }

  Future<ParentUser?> getCoparent() async {
    final profile = await _supabase
        .from('parents')
        .select('family_id')
        .eq('id', _supabase.auth.currentUser!.id)
        .single();
    final familyId = profile['family_id'] as String?;
    if (familyId == null) return null;
    final response = await _supabase
        .from('parents')
        .select()
        .eq('family_id', familyId)
        .neq('id', _supabase.auth.currentUser!.id)
        .maybeSingle();
    if (response == null) return null;
    return ParentUser.fromMap(response);
  }

  Future<List<ParentInvite>> getPendingInvites(String familyId) async {
    final response = await _supabase
        .from('parent_invites')
        .select()
        .eq('family_id', familyId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return response.map((m) => ParentInvite.fromMap(m)).toList();
  }

  Future<List<ParentUser>> getCoParents(String familyId) async {
    final response = await _supabase
        .from('parents')
        .select()
        .eq('family_id', familyId)
        .neq('id', _supabase.auth.currentUser!.id);
    return response.map((m) => ParentUser.fromMap(m)).toList();
  }

  Future<List<ParentInvite>> getMyInvites() async {
    final email = _supabase.auth.currentUser!.email ?? '';
    if (email.isEmpty) return [];
    final response = await _supabase
        .from('parent_invites')
        .select()
        .eq('invitee_email', email)
        .order('created_at', ascending: false);
    return response.map((m) => ParentInvite.fromMap(m)).toList();
  }

  Future<ParentInvite> invite({
    required String familyId,
    required String email,
  }) async {
    final response = await _supabase
        .from('parent_invites')
        .insert({
          'family_id': familyId,
          'inviter_id': _supabase.auth.currentUser!.id,
          'invitee_email': email,
          'status': 'pending',
        })
        .select()
        .single();
    return ParentInvite.fromMap(response);
  }

  Future<void> acceptInvite(String inviteId) async {
    final invite = await _supabase
        .from('parent_invites')
        .select('family_id, invitee_email')
        .eq('id', inviteId)
        .single();
    final email = invite['invitee_email'] as String;
    await _supabase
        .from('parent_invites')
        .update({'status': 'accepted'})
        .eq('id', inviteId);
    final parent = await _supabase
        .from('parents')
        .select('id')
        .eq('email', email)
        .single();
    await _supabase
        .from('parents')
        .update({'family_id': invite['family_id']})
        .eq('id', parent['id']);
  }

  Future<void> cancelInvite(String inviteId) async {
    await revokeInvite(inviteId);
  }

  Future<void> removeCoparent(String coparentId) async {
    await _supabase
        .from('parents')
        .update({'family_id': null})
        .eq('id', coparentId);
  }
}
