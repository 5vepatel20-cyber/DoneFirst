import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class ProfileService {
  final _supabase = Supabase.instance.client;

  Future<ParentUser> getProfile() async {
    final response = await _supabase
        .from('parents')
        .select()
        .eq('id', _supabase.auth.currentUser!.id)
        .single();
    return ParentUser.fromMap(response);
  }

  Future<ParentUser?> getParentProfile() async {
    final response = await _supabase
        .from('parents')
        .select()
        .eq('id', _supabase.auth.currentUser!.id)
        .maybeSingle();
    if (response == null) return null;
    return ParentUser.fromMap(response);
  }

  Future<String?> getFamilyName() async {
    final parent = await _supabase
        .from('parents')
        .select('family_id')
        .eq('id', _supabase.auth.currentUser!.id)
        .single();
    if (parent['family_id'] == null) return null;
    final family = await _supabase
        .from('families')
        .select('name')
        .eq('id', parent['family_id'])
        .single();
    return family['name'] as String?;
  }

  Future<void> updateParentName(String name) async {
    await updateDisplayName(name);
  }

  Future<void> updateFamilyName(String name) async {
    final parent = await _supabase
        .from('parents')
        .select('family_id')
        .eq('id', _supabase.auth.currentUser!.id)
        .single();
    if (parent['family_id'] != null) {
      await _supabase
          .from('families')
          .update({'name': name})
          .eq('id', parent['family_id']);
    }
  }

  Future<void> updateDisplayName(String displayName) async {
    await _supabase
        .from('parents')
        .update({'display_name': displayName})
        .eq('id', _supabase.auth.currentUser!.id);
  }

  Future<void> updateEmail(String newEmail) async {
    // Two independent writes (Supabase Auth + parents table).
    // Run them in parallel so the email-change flow doesn't pay
    // 2× the round-trip latency for two writes that don't depend
    // on each other's results.
    await Future.wait<Object?>([
      _supabase.auth.updateUser(UserAttributes(email: newEmail)),
      _supabase
          .from('parents')
          .update({'email': newEmail})
          .eq('id', _supabase.auth.currentUser!.id),
    ]);
  }

  Future<void> deleteAccount() async {
    final userId = _supabase.auth.currentUser!.id;
    await _supabase.from('parents').delete().eq('id', userId);
    await _supabase.auth.admin.deleteUser(userId);
  }
}
