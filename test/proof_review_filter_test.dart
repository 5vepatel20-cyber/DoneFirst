// Stable-string guard for the proof review filter logic. We don't
// import the screen directly (it pulls in Supabase.instance at
// construction), but we can verify the underlying model fields the
// filter relies on are stable, plus the search-text token set.
import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/models/models.dart';

void main() {
  test('HomeworkSession exposes the fields the review filter uses', () {
    final s = HomeworkSession(
      id: 's1',
      childId: 'c1',
      parentId: 'p1',
      startedAt: DateTime.utc(2026, 6, 1, 14, 0),
      endedAt: DateTime.utc(2026, 6, 1, 14, 30),
      status: 'completed',
      minLockMinutes: 30,
      approvalMode: 'balanced',
    );
    // Fields the screen's _applyFilters reads:
    expect(s.status, isA<String>());
    expect(s.approvalMode, isA<String>());
    expect(s.isCompleted, isA<bool>());
    expect(s.startedAt, isA<DateTime>());
  });

  test('search tokens a parent would type are case-insensitive substrings', () {
    // Simulate the predicate used in _applyFilters: case-insensitive
    // substring match on status or approval mode.
    bool matches(HomeworkSession s, String q) {
      final needle = q.trim().toLowerCase();
      if (needle.isEmpty) return true;
      return s.status.toLowerCase().contains(needle) ||
          s.approvalMode.toLowerCase().contains(needle);
    }

    final s = HomeworkSession(
      id: 's1',
      childId: 'c1',
      parentId: 'p1',
      startedAt: DateTime.utc(2026, 6, 1),
      endedAt: null,
      status: 'completed',
      minLockMinutes: 30,
      approvalMode: 'balanced',
    );
    expect(matches(s, 'comp'), isTrue); // status prefix
    expect(matches(s, 'BAL'), isTrue); // approval mode upper
    expect(matches(s, 'strict'), isFalse); // no match
    expect(matches(s, ''), isTrue); // empty query is "match all"
  });
}
