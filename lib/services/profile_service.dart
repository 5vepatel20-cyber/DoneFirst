import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  final _supabase = Supabase.instance.client;

  Future<void> updateParentName(String displayName) async {
    await _supabase
        .from('parents')
        .update({'display_name': displayName})
        .eq('id', _supabase.auth.currentUser!.id);
  }

  Future<Map<String, dynamic>?> getParentProfile() async {
    return await _supabase
        .from('parents')
        .select('id, email, display_name, role')
        .eq('id', _supabase.auth.currentUser!.id)
        .maybeSingle();
  }

  Future<void> updateFamilyName(String familyName) async {
    final record = await _supabase
        .from('parents')
        .select('family_id')
        .eq('id', _supabase.auth.currentUser!.id)
        .single();
    if (record['family_id'] != null) {
      await _supabase
          .from('families')
          .update({'name': familyName})
          .eq('id', record['family_id']);
    }
  }

  Future<String?> getFamilyName() async {
    final record = await _supabase
        .from('parents')
        .select('family_id')
        .eq('id', _supabase.auth.currentUser!.id)
        .single();
    if (record['family_id'] == null) return null;
    final family = await _supabase
        .from('families')
        .select('name')
        .eq('id', record['family_id'])
        .single();
    return family['name'] as String?;
  }
}
