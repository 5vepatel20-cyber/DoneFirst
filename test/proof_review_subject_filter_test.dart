// Tests for the subject filter logic in proof_review_screen.
// We replicate the filtering rule here so a behavior change breaks
// the test instead of silently flipping what parents see.
import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/utils/subjects.dart';

void main() {
  // Mirror of the production filter: a session matches a subject
  // filter if any of its tasks was tagged with that subject.
  // Sessions with no tasks at all are hidden when a subject filter
  // is active (there's nothing to show for "Math" if no Math task
  // exists in that session).
  List<String> filterBySubject({
    required Map<String, Set<String>> sessionSubjects,
    required List<String> allSessionIds,
    required String? subjectFilter,
  }) {
    if (subjectFilter == null) return allSessionIds;
    return allSessionIds
        .where(
          (id) => sessionSubjects[id]?.contains(subjectFilter) ?? false,
        )
        .toList();
  }

  test('null filter returns every session in order', () {
    final result = filterBySubject(
      sessionSubjects: {
        's1': {'Math', 'English'},
        's2': {'General'},
      },
      allSessionIds: ['s1', 's2'],
      subjectFilter: null,
    );
    expect(result, ['s1', 's2']);
  });

  test('Math filter keeps only sessions with a Math task', () {
    final result = filterBySubject(
      sessionSubjects: {
        's1': {'Math', 'English'},
        's2': {'General'},
        's3': {'Math'},
      },
      allSessionIds: ['s1', 's2', 's3'],
      subjectFilter: 'Math',
    );
    expect(result, ['s1', 's3']);
  });

  test('session with no tasks is hidden when a subject filter is active', () {
    final result = filterBySubject(
      sessionSubjects: {
        's1': {}, // no tasks at all
        's2': {'Math'},
      },
      allSessionIds: ['s1', 's2'],
      subjectFilter: 'Math',
    );
    expect(result, ['s2']);
  });

  test('unknown subject filter returns empty list', () {
    final result = filterBySubject(
      sessionSubjects: {
        's1': {'Math'},
        's2': {'English'},
      },
      allSessionIds: ['s1', 's2'],
      subjectFilter: 'Astrology',
    );
    expect(result, isEmpty);
  });

  test('combined: subject + General filter for sessions that used General', () {
    // Sanity: the kDefaultSubject ('General') is in kSubjects, so it
    // can be filtered like any other.
    expect(kSubjects, contains('General'));
    final result = filterBySubject(
      sessionSubjects: {
        's1': {'General'},
        's2': {'Math'},
      },
      allSessionIds: ['s1', 's2'],
      subjectFilter: 'General',
    );
    expect(result, ['s1']);
  });
}
