import 'package:supabase_flutter/supabase_flutter.dart';

class ScheduleService {
  final _supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getSchedules(String childId) async {
    final response = await _supabase
        .from('recurring_schedules')
        .select()
        .eq('child_id', childId)
        .order('day_of_week');
    return response;
  }

  Future<void> addSchedule({
    required String childId,
    required int dayOfWeek,
    required int durationMinutes,
    required String approvalMode,
  }) async {
    await _supabase.from('recurring_schedules').insert({
      'child_id': childId,
      'day_of_week': dayOfWeek,
      'duration_minutes': durationMinutes,
      'approval_mode': approvalMode,
    });
  }

  Future<void> removeSchedule(String scheduleId) async {
    await _supabase.from('recurring_schedules').delete().eq('id', scheduleId);
  }

  Future<List<Map<String, dynamic>>> getTodaysSchedules(String childId) async {
    final today = DateTime.now().weekday;
    final response = await _supabase
        .from('recurring_schedules')
        .select()
        .eq('child_id', childId)
        .eq('day_of_week', today);
    return response;
  }
}

const List<String> weekdayNames = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];
