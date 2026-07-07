import 'package:supabase_flutter/supabase_flutter.dart';

class StreakService {
  final _supabase = Supabase.instance.client;

  Future<int> computeStreak(String childId) async {
    final sessions = await _supabase
        .from('homework_sessions')
        .select('started_at')
        .eq('child_id', childId)
        .eq('status', 'completed')
        .order('started_at', ascending: false);

    if (sessions.isEmpty) return 0;

    final dates = <DateTime>{};
    for (final s in sessions) {
      final started = DateTime.tryParse(s['started_at'] as String? ?? '');
      if (started != null) {
        dates.add(DateTime(started.year, started.month, started.day));
      }
    }

    final sorted = dates.toList()..sort((a, b) => b.compareTo(a));
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    if (sorted.first != todayDate &&
        sorted.first != todayDate.subtract(const Duration(days: 1))) {
      return 0;
    }

    int streak = 0;
    DateTime expected = sorted.first == todayDate
        ? todayDate
        : todayDate.subtract(const Duration(days: 1));

    for (final d in sorted) {
      if (d == expected) {
        streak++;
        expected = expected.subtract(const Duration(days: 1));
      } else if (d.isBefore(expected)) {
        break;
      }
    }

    return streak;
  }
}
