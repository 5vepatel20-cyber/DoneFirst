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

  Future<Map<String, dynamic>?> getParentProfile() async {
    final response = await _supabase
        .from('parents')
        .select()
        .eq('id', _supabase.auth.currentUser!.id)
        .maybeSingle();
    return response;
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
    await _supabase.auth.updateUser(UserAttributes(email: newEmail));
    await _supabase
        .from('parents')
        .update({'email': newEmail})
        .eq('id', _supabase.auth.currentUser!.id);
  }

  Future<void> deleteAccount() async {
    final userId = _supabase.auth.currentUser!.id;
    await _supabase.from('parents').delete().eq('id', userId);
    await _supabase.auth.admin.deleteUser(userId);
  }
}
