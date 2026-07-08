import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class StreakService {
  final _supabase = Supabase.instance.client;

  Future<int> computeStreak(String childId) async {
    return getStreakCount(childId);
  }

  Future<int> getStreakCount(String childId) async {
    final today = DateTime.now();
    final thirtyDaysAgo = today.subtract(const Duration(days: 30));
    final response = await _supabase
        .from('homework_sessions')
        .select('started_at')
        .eq('child_id', childId)
        .eq('status', 'completed')
        .gte('started_at', thirtyDaysAgo.toIso8601String())
        .order('started_at', ascending: false);
    final dates = response
        .map((m) => DateTime.parse(m['started_at'] as String))
        .toSet()
        .toList();
    dates.sort((a, b) => b.compareTo(a));
    if (dates.isEmpty) return 0;
    int streak = 0;
    var check = today;
    for (final d in dates) {
      if (d.year == check.year && d.month == check.month && d.day == check.day) {
        streak++;
        check = check.subtract(const Duration(days: 1));
      } else if (d.isBefore(check)) {
        break;
      }
    }
    return streak;
  }

  Future<List<HomeworkSession>> getRecentSessions(
    String childId, {
    int limit = 30,
  }) async {
    final response = await _supabase
        .from('homework_sessions')
        .select()
        .eq('child_id', childId)
        .order('started_at', ascending: false)
        .limit(limit);
    return response.map((m) => HomeworkSession.fromMap(m)).toList();
  }
}
