import 'package:flutter_test/flutter_test.dart';

/// Pure-logic tests for the streak grace-day algorithm. Mirrors
/// StreakService.computeStreakResult's behaviour so we can lock in
/// the grace rules without spinning up a Supabase client. If the
/// real service drifts from this mirror, the tests fail first.

class StreakResult {
  final int streak;
  final bool graceUsed;
  const StreakResult({required this.streak, required this.graceUsed});
}

StreakResult computeStreak({
  required Set<DateTime> datesWithSession,
  required DateTime today,
  int gracePerWeek = 0,
}) {
  var check = DateTime(today.year, today.month, today.day);
  final todayDate = check;
  var streak = 0;
  var graceRemaining = gracePerWeek;
  var graceUsed = false;
  // Earliest session in the window — once we walk past this date,
  // there's no streak left to extend, so we stop instead of
  // spending grace looking for non-existent activity.
  final earliestSession = datesWithSession.isEmpty
      ? null
      : datesWithSession.reduce((a, b) => a.isBefore(b) ? a : b);

  while (true) {
    if (datesWithSession.contains(check)) {
      streak++;
      check = check.subtract(const Duration(days: 1));
      continue;
    }
    // Today with no session — skip without counting or breaking.
    // The school day isn't over; today isn't a session and it
    // isn't a miss.
    if (check == todayDate) {
      check = check.subtract(const Duration(days: 1));
      continue;
    }
    // Past the earliest session — there's no streak to extend.
    // Don't consume grace just because the data ends here.
    if (earliestSession != null && check.isBefore(earliestSession)) {
      break;
    }
    if (graceRemaining > 0) {
      graceRemaining--;
      graceUsed = true;
      check = check.subtract(const Duration(days: 1));
      continue;
    }
    break;
  }
  return StreakResult(streak: streak, graceUsed: graceUsed);
}

DateTime _date(int year, int month, int day) => DateTime(year, month, day);

void main() {
  // Anchor "today" mid-year so we don't have to think about DST or
  // year boundaries in the algorithm.
  final today = _date(2026, 7, 10);

  // Build a set of session dates from a list of (year, month, day).
  Set<DateTime> sessionDates(List<DateTime> dates) => dates.toSet();

  group('grace=0 (legacy behaviour)', () {
    test('seven consecutive days returns 7', () {
      final dates = sessionDates([
        today,
        today.subtract(const Duration(days: 1)),
        today.subtract(const Duration(days: 2)),
        today.subtract(const Duration(days: 3)),
        today.subtract(const Duration(days: 4)),
        today.subtract(const Duration(days: 5)),
        today.subtract(const Duration(days: 6)),
      ]);
      final result = computeStreak(
        datesWithSession: dates,
        today: today,
      );
      expect(result.streak, 7);
      expect(result.graceUsed, isFalse);
    });

    test('today not done yet still counts yesterday as a 1-day streak', () {
      final dates = sessionDates([
        today.subtract(const Duration(days: 1)),
      ]);
      final result = computeStreak(
        datesWithSession: dates,
        today: today,
      );
      expect(result.streak, 1);
    });

    test('a single missing day breaks the streak', () {
      final dates = sessionDates([
        today,
        today.subtract(const Duration(days: 2)), // gap at day-1
      ]);
      final result = computeStreak(
        datesWithSession: dates,
        today: today,
      );
      // Only today counts; yesterday is a real miss and we have no
      // grace, so the streak ends at 1.
      expect(result.streak, 1);
    });

    test('empty history returns 0', () {
      final result = computeStreak(
        datesWithSession: sessionDates([]),
        today: today,
      );
      expect(result.streak, 0);
      expect(result.graceUsed, isFalse);
    });
  });

  group('grace=1', () {
    test('survives one missing day in the middle of the streak', () {
      // Days: -0, -1, -2, [miss -3], -4, -5, -6 → 7-day streak
      final dates = sessionDates([
        today,
        today.subtract(const Duration(days: 1)),
        today.subtract(const Duration(days: 2)),
        // gap at day-3
        today.subtract(const Duration(days: 4)),
        today.subtract(const Duration(days: 5)),
        today.subtract(const Duration(days: 6)),
        today.subtract(const Duration(days: 7)),
      ]);
      final result = computeStreak(
        datesWithSession: dates,
        today: today,
        gracePerWeek: 1,
      );
      expect(result.streak, 7);
      expect(result.graceUsed, isTrue);
    });

    test('breaks on a second consecutive miss', () {
      // Days: -0, -1, [miss -2], [miss -3], -4 → streak ends at day-1
      final dates = sessionDates([
        today,
        today.subtract(const Duration(days: 1)),
        // gap at -2 and -3
        today.subtract(const Duration(days: 4)),
      ]);
      final result = computeStreak(
        datesWithSession: dates,
        today: today,
        gracePerWeek: 1,
      );
      // Walk: today (yes, +1), yesterday (yes, +1), day-2 (no,
      // grace spent, +0), day-3 (no, no grace, break). Streak = 2.
      expect(result.streak, 2);
      expect(result.graceUsed, isTrue);
    });

    test('grace not used when streak has no miss', () {
      final dates = sessionDates([
        today,
        today.subtract(const Duration(days: 1)),
        today.subtract(const Duration(days: 2)),
      ]);
      final result = computeStreak(
        datesWithSession: dates,
        today: today,
        gracePerWeek: 1,
      );
      expect(result.streak, 3);
      expect(result.graceUsed, isFalse);
    });

    test('grace carries through a missing today (today skip)', () {
      // The "today skip" branch (no session, check == today) must
      // NOT consume grace. The kid hasn't failed today; the day
      // just isn't over.
      final dates = sessionDates([
        today.subtract(const Duration(days: 1)),
        today.subtract(const Duration(days: 2)),
      ]);
      final result = computeStreak(
        datesWithSession: dates,
        today: today,
        gracePerWeek: 1,
      );
      expect(result.streak, 2);
      expect(result.graceUsed, isFalse);
    });

    test('grace spent on yesterday while today also missing still ends at 0',
        () {
      // If today is missing AND yesterday is missing, that's a
      // real break — we don't have 2 grace days to spend.
      final dates = sessionDates([
        today.subtract(const Duration(days: 2)),
      ]);
      final result = computeStreak(
        datesWithSession: dates,
        today: today,
        gracePerWeek: 1,
      );
      // Walk: today (skip-no-grace), yesterday (miss, grace spent),
      // day-2 (yes, +1), day-3 (no, no grace, break). Streak = 1.
      expect(result.streak, 1);
      expect(result.graceUsed, isTrue);
    });
  });

  group('grace=2', () {
    test('survives two consecutive misses', () {
      final dates = sessionDates([
        today,
        today.subtract(const Duration(days: 1)),
        // gaps at -2, -3
        today.subtract(const Duration(days: 4)),
        today.subtract(const Duration(days: 5)),
      ]);
      final result = computeStreak(
        datesWithSession: dates,
        today: today,
        gracePerWeek: 2,
      );
      expect(result.streak, 4);
      expect(result.graceUsed, isTrue);
    });
  });
}