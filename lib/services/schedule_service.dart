import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class ScheduleService {
  final _supabase = Supabase.instance.client;

  Future<RecurringSchedule> addSchedule({
    required String childId,
    required int dayOfWeek,
    required int durationMinutes,
    required String approvalMode,
  }) async {
    final response = await _supabase
        .from('recurring_schedules')
        .insert({
          'child_id': childId,
          'day_of_week': dayOfWeek,
          'duration_minutes': durationMinutes,
          'approval_mode': approvalMode,
        })
        .select()
        .single();
    return RecurringSchedule.fromMap(response);
  }

  Future<List<RecurringSchedule>> getSchedules(String childId) async {
    final response = await _supabase
        .from('recurring_schedules')
        .select()
        .eq('child_id', childId)
        .order('day_of_week', ascending: true);
    return response.map((m) => RecurringSchedule.fromMap(m)).toList();
  }

  Future<void> updateSchedule(String scheduleId,
      {int? durationMinutes, String? approvalMode}) async {
    await _supabase
        .from('recurring_schedules')
        .update({
          ?'duration_minutes': durationMinutes,
          ?'approval_mode': approvalMode,
        })
        .eq('id', scheduleId);
  }

  Future<void> deleteSchedule(String scheduleId) async {
    await _supabase
        .from('recurring_schedules')
        .delete()
        .eq('id', scheduleId);
  }

  Future<List<RecurringSchedule>> getTodaySchedules([String? childId]) async {
    final today = DateTime.now().weekday - 1;
    final response = await _supabase
        .from('recurring_schedules')
        .select()
        .eq('day_of_week', today);
    final all = response.map((m) => RecurringSchedule.fromMap(m)).toList();
    if (childId != null) {
      return all.where((s) => s.childId == childId).toList();
    }
    return all;
  }
}
