import 'package:supabase_flutter/supabase_flutter.dart';

class LockPresetService {
  final _supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getPresets() async {
    final response = await _supabase
        .from('lock_presets')
        .select()
        .eq('parent_id', _supabase.auth.currentUser!.id)
        .order('created_at', ascending: false);
    return response;
  }

  Future<Map<String, dynamic>> savePreset({
    required String name,
    required int minLockMinutes,
    required int maxLiftMinutes,
    required String approvalMode,
    required List<String> selectedPacks,
  }) async {
    final response = await _supabase
        .from('lock_presets')
        .insert({
          'parent_id': _supabase.auth.currentUser!.id,
          'name': name,
          'min_lock_minutes': minLockMinutes,
          'max_lift_minutes': maxLiftMinutes,
          'approval_mode': approvalMode,
          'selected_packs': selectedPacks,
        })
        .select()
        .single();
    return response;
  }

  Future<void> deletePreset(String presetId) async {
    await _supabase.from('lock_presets').delete().eq('id', presetId);
  }
}
