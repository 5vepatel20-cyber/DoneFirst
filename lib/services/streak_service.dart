import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

/// Result of a streak computation. [graceUsed] is true when the
/// streak counted at least one missed day as grace — useful for the
/// kid UX to show a "1 grace day used" indicator so the kid (and
/// the parent) knows the streak is being held up by a grace pass.
class StreakResult {
  final int streak;
  final bool graceUsed;

  const StreakResult({required this.streak, required this.graceUsed});
}

class StreakService {
  final _supabase = Supabase.instance.client;

  /// Computes the streak and returns just the count. Convenience
  /// wrapper for callers that don't need the grace flag.
  Future<int> computeStreak(String childId) async {
    final result = await computeStreakResult(childId);
    return result.streak;
  }

  /// Computes the streak with optional grace. When [gracePerWeek]
  /// is 0, behavior is identical to the original: streak ends on
  /// the first missed day. When [gracePerWeek] > 0, the algorithm
  /// allows up to that many missed days anywhere in the streak
  /// without breaking. Each grace day is "spent" once and only
  /// resets when the streak itself resets — so a single grace can
  /// carry the kid through one sick day or weekend but a second
  /// miss in a row still breaks. This matches how most parents
  /// think about grace ("every kid deserves one off-day") without
  /// making the streak meaningless.
  ///
  /// Today's missing session does NOT consume grace — the day
  /// isn't over yet, so it's neither a session nor a miss for
  /// streak purposes.
  Future<StreakResult> computeStreakResult(
    String childId, {
    int gracePerWeek = 0,
  }) async {
    final today = _truncateToDate(DateTime.now());
    final thirtyDaysAgo = today.subtract(const Duration(days: 30));
    final response = await _supabase
        .from('homework_sessions')
        .select('started_at')
        .eq('child_id', childId)
        .eq('status', 'completed')
        .gte('started_at', thirtyDaysAgo.toIso8601String())
        .order('started_at', ascending: false);

    // Convert to a Set<DateTime> of truncated-to-date values so
    // membership lookups are O(1) and "did the kid do homework on
    // date X" stays a one-line check.
    final datesWithSession = response
        .map((m) => _truncateToDate(DateTime.parse(m['started_at'] as String)))
        .toSet();

    // Earliest session in the window — once we walk past this date,
    // there's no streak left to extend, so we stop instead of
    // spending grace looking for non-existent activity.
    final earliestSession = datesWithSession.isEmpty
        ? null
        : datesWithSession.reduce((a, b) => a.isBefore(b) ? a : b);

    var check = today;
    var streak = 0;
    var graceRemaining = gracePerWeek;
    var graceUsed = false;

    while (true) {
      if (datesWithSession.contains(check)) {
        streak++;
        check = check.subtract(const Duration(days: 1));
        continue;
      }
      // Today with no session yet — skip past it without counting
      // or breaking. The school day isn't over; today is neither
      // a session nor a miss for streak purposes.
      if (check == today) {
        check = check.subtract(const Duration(days: 1));
        continue;
      }
      // Past the earliest session — no streak to extend. Don't
      // consume grace here; grace only matters while there's
      // history to bridge.
      if (earliestSession != null && check.isBefore(earliestSession)) {
        break;
      }
      // Real miss. Spend a grace day if we have one.
      if (graceRemaining > 0) {
        graceRemaining--;
        graceUsed = true;
        check = check.subtract(const Duration(days: 1));
        continue;
      }
      // No grace left — streak ends here.
      break;
    }
    return StreakResult(streak: streak, graceUsed: graceUsed);
  }

  /// Backwards-compatible name preserved for callers that
  /// imported this directly. Delegates to [computeStreakResult].
  Future<int> getStreakCount(String childId) async {
    final result = await computeStreakResult(childId);
    return result.streak;
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

  /// Strip the time component so two timestamps on the same
  /// calendar day compare equal. Local time is used throughout —
  /// the kid's "did homework" boundary is their local calendar
  /// day, not UTC.
  DateTime _truncateToDate(DateTime d) => DateTime(d.year, d.month, d.day);
}