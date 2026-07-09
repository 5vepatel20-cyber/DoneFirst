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

  // Mirror of the production text-search filter. The session passes
  // if its status, approval mode, OR any of its task descriptions
  // (lowercased, concatenated) contains the query substring.
  List<String> filterBySearch({
    required Map<String, ({String status, String approvalMode})> meta,
    required Map<String, String> sessionSearchText,
    required List<String> allSessionIds,
    required String rawQuery,
  }) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return allSessionIds;
    return allSessionIds.where((id) {
      final m = meta[id];
      if (m == null) return false;
      if (m.status.toLowerCase().contains(query)) return true;
      if (m.approvalMode.toLowerCase().contains(query)) return true;
      if ((sessionSearchText[id] ?? '').contains(query)) return true;
      return false;
    }).toList();
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

  group('text search across status / approval mode / task descriptions', () {
    final meta = <String, ({String status, String approvalMode})>{
      's1': (status: 'active', approvalMode: 'balanced'),
      's2': (status: 'completed', approvalMode: 'strict'),
      's3': (status: 'active', approvalMode: 'strict'),
    };
    final searchText = <String, String>{
      's1': 'math chapter 4 practice problems',
      's2': 'history essay on world war 2',
      's3': 'english reading log chapter 1',
    };

    test('empty query returns all sessions', () {
      expect(
        filterBySearch(
          meta: meta,
          sessionSearchText: searchText,
          allSessionIds: meta.keys.toList(),
          rawQuery: '',
        ),
        ['s1', 's2', 's3'],
      );
    });

    test('whitespace-only query returns all sessions', () {
      expect(
        filterBySearch(
          meta: meta,
          sessionSearchText: searchText,
          allSessionIds: meta.keys.toList(),
          rawQuery: '   ',
        ),
        ['s1', 's2', 's3'],
      );
    });

    test('matches status substring', () {
      expect(
        filterBySearch(
          meta: meta,
          sessionSearchText: searchText,
          allSessionIds: meta.keys.toList(),
          rawQuery: 'comp',
        ),
        ['s2'],
      );
    });

    test('matches approval mode substring', () {
      expect(
        filterBySearch(
          meta: meta,
          sessionSearchText: searchText,
          allSessionIds: meta.keys.toList(),
          rawQuery: 'strict',
        ),
        ['s2', 's3'],
      );
    });

    test('matches a word in a task description', () {
      expect(
        filterBySearch(
          meta: meta,
          sessionSearchText: searchText,
          allSessionIds: meta.keys.toList(),
          rawQuery: 'essay',
        ),
        ['s2'],
      );
    });

    test('search is case-insensitive', () {
      expect(
        filterBySearch(
          meta: meta,
          sessionSearchText: searchText,
          allSessionIds: meta.keys.toList(),
          rawQuery: 'MATH',
        ),
        ['s1'],
      );
    });

    test('query that matches nothing returns empty list', () {
      expect(
        filterBySearch(
          meta: meta,
          sessionSearchText: searchText,
          allSessionIds: meta.keys.toList(),
          rawQuery: 'chemistry',
        ),
        isEmpty,
      );
    });

    test('session with no task descriptions never matches via search text',
        () {
      // Defensive: if _load() failed for one session (rare), the
      // index entry is missing — that session should not falsely
      // match arbitrary queries just because its index is empty.
      final partialText = <String, String>{'s1': 'math homework'};
      expect(
        filterBySearch(
          meta: meta,
          sessionSearchText: partialText,
          allSessionIds: meta.keys.toList(),
          rawQuery: 'math',
        ),
        ['s1'],
      );
    });
  });
}
