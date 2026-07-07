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

  Future<List<Map<String, dynamic>>> getTodaySchedules() async {
    final today = DateTime.now().weekday;
    final parentId = _supabase.auth.currentUser!.id;
    final family = await _supabase
        .from('parents')
        .select('family_id')
        .eq('id', parentId)
        .single();
    if (family['family_id'] == null) return [];
    final children = await _supabase
        .from('children')
        .select('id')
        .eq('family_id', family['family_id']);
    final childIds = children.map((c) => c['id'] as String).toList();
    if (childIds.isEmpty) return [];
    final response = await _supabase
        .from('recurring_schedules')
        .select()
        .inFilter('child_id', childIds)
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
