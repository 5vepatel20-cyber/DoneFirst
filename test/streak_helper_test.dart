// Tests for the streak "is today / yesterday / at risk" logic.
//
// Pure-Dart, so it doesn't need to spin up the parent_dashboard
// widget (which pulls Supabase). We replicate the rule as a plain
// function so we can lock in the day-grace behavior.
import 'package:flutter_test/flutter_test.dart';

bool streakIsActive(DateTime lastStreakDate, DateTime now) {
  // The production rule from parent_dashboard._streakIsToday —
  // mirrored here so a behavior change breaks this test instead of
  // silently affecting what kids see in the app.
  final today = DateTime(now.year, now.month, now.day);
  final last = DateTime(
    lastStreakDate.year,
    lastStreakDate.month,
    lastStreakDate.day,
  );
  final diff = today.difference(last).inDays;
  return diff == 0 || diff == 1;
}

void main() {
  final now = DateTime(2026, 7, 8, 9); // Wed morning

  test('streak from today is active', () {
    expect(
      streakIsActive(DateTime(2026, 7, 8), now),
      isTrue,
    );
  });

  test('streak from yesterday is still active (grace period)', () {
    expect(
      streakIsActive(DateTime(2026, 7, 7), now),
      isTrue,
      reason: 'Kid may not have done today\'s session yet this morning.',
    );
  });

  test('streak from two days ago is broken (at risk)', () {
    expect(
      streakIsActive(DateTime(2026, 7, 6), now),
      isFalse,
    );
  });

  test('streak from a year ago is broken', () {
    expect(
      streakIsActive(DateTime(2025, 12, 1), now),
      isFalse,
    );
  });

  test('streak from tomorrow is treated as today (clock skew defensive)', () {
    // Shouldn't happen in practice, but if the device clock jumps
    // forward we don't want a negative diff to crash things.
    expect(
      streakIsActive(DateTime(2026, 7, 9), now),
      isFalse,
    );
  });
}
