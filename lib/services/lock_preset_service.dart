import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class LockPresetService {
  final _supabase = Supabase.instance.client;

  Future<LockPreset> createPreset({
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
    return LockPreset.fromMap(response);
  }

  Future<List<LockPreset>> getPresets() async {
    final response = await _supabase
        .from('lock_presets')
        .select()
        .eq('parent_id', _supabase.auth.currentUser!.id)
        .order('created_at', ascending: false);
    return response.map((m) => LockPreset.fromMap(m)).toList();
  }

  Future<void> updatePreset(String presetId,
      {String? name,
      int? minLockMinutes,
      int? maxLiftMinutes,
      String? approvalMode,
      List<String>? selectedPacks}) async {
    await _supabase
        .from('lock_presets')
        .update({
          if (name != null) 'name': name,
          if (minLockMinutes != null) 'min_lock_minutes': minLockMinutes,
          if (maxLiftMinutes != null) 'max_lift_minutes': maxLiftMinutes,
          if (approvalMode != null) 'approval_mode': approvalMode,
          if (selectedPacks != null) 'selected_packs': selectedPacks,
        })
        .eq('id', presetId);
  }

  Future<void> deletePreset(String presetId) async {
    await _supabase.from('lock_presets').delete().eq('id', presetId);
  }
}
