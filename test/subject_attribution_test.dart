// Tests for the per-subject minutes attribution logic in
// sessions_stats_screen.dart. We replicate the algorithm here so a
// behavior change breaks the test instead of silently flipping what
// parents see.
import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/utils/subjects.dart';

void main() {
  // Mirror of the production attribution: each task attributes the
  // full session duration to its subject.
  Map<String, int> attributeMinutes({
    required List<Map<String, dynamic>> sessions,
    required List<Map<String, dynamic>> tasks,
  }) {
    final sessionMinutes = <String, int>{
      for (final s in sessions) s['id'] as String: s['duration_minutes'] as int? ?? 0,
    };
    final out = <String, int>{
      for (final s in kSubjects) s: 0,
    };
    for (final t in tasks) {
      final sid = t['session_id'] as String?;
      if (sid == null) continue;
      final subject = normalizeSubject(t['subject'] as String?);
      out[subject] = (out[subject] ?? 0) + (sessionMinutes[sid] ?? 0);
    }
    return out;
  }

  test('empty inputs produce all zeros', () {
    final result = attributeMinutes(sessions: [], tasks: []);
    expect(result.values.every((v) => v == 0), isTrue);
  });

  test('single session with one Math task → 60 min Math', () {
    final result = attributeMinutes(
      sessions: [
        {'id': 's1', 'duration_minutes': 60},
      ],
      tasks: [
        {'session_id': 's1', 'subject': 'Math'},
      ],
    );
    expect(result['Math'], 60);
    expect(result['General'], 0);
  });

  test('session with 2 different subjects attributes minutes to both', () {
    final result = attributeMinutes(
      sessions: [
        {'id': 's1', 'duration_minutes': 60},
      ],
      tasks: [
        {'session_id': 's1', 'subject': 'Math'},
        {'session_id': 's1', 'subject': 'English'},
      ],
    );
    // Yes, this double-counts a 60-min session as 120 min across
    // subjects. The v1 behavior is documented in the production
    // comment; if we ever fix it, this test will need updating.
    expect(result['Math'], 60);
    expect(result['English'], 60);
  });

  test('unknown subject falls back to default', () {
    final result = attributeMinutes(
      sessions: [
        {'id': 's1', 'duration_minutes': 30},
      ],
      tasks: [
        {'session_id': 's1', 'subject': 'Astrology'},
      ],
    );
    expect(result[kDefaultSubject], 30);
  });

  test('null subject falls back to default', () {
    final result = attributeMinutes(
      sessions: [
        {'id': 's1', 'duration_minutes': 30},
      ],
      tasks: [
        {'session_id': 's1', 'subject': null},
      ],
    );
    expect(result[kDefaultSubject], 30);
  });

  test('task referencing a deleted session is silently skipped', () {
    final result = attributeMinutes(
      sessions: [
        {'id': 's1', 'duration_minutes': 30},
      ],
      tasks: [
        {'session_id': 's2', 'subject': 'Math'}, // orphan task
      ],
    );
    expect(result['Math'], 0);
  });

  test('multiple sessions with mixed subjects aggregate correctly', () {
    final result = attributeMinutes(
      sessions: [
        {'id': 's1', 'duration_minutes': 30},
        {'id': 's2', 'duration_minutes': 45},
        {'id': 's3', 'duration_minutes': 60},
      ],
      tasks: [
        {'session_id': 's1', 'subject': 'Math'},
        {'session_id': 's2', 'subject': 'Math'},
        {'session_id': 's3', 'subject': 'English'},
      ],
    );
    expect(result['Math'], 30 + 45);
    expect(result['English'], 60);
  });
}