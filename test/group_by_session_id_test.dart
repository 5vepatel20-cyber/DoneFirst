// Tests for the pure helper used by data_export_service.dart to
// group child-side rows (tasks / proofs / break_requests) by their
// owning session_id after a single batched inFilter query. We
// replicate the helper here because the production class depends
// on Supabase and can't be exercised in a pure-Dart unit test.
import 'package:flutter_test/flutter_test.dart';

Map<String, List<Map<String, dynamic>>> groupBySessionId(
  List<Map<String, dynamic>> rows,
) {
  final out = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final sid = row['session_id'] as String?;
    if (sid == null) continue;
    out.putIfAbsent(sid, () => []).add(row);
  }
  return out;
}

void main() {
  test('empty input → empty map', () {
    expect(groupBySessionId(const []), isEmpty);
  });

  test('rows with same session_id land in the same list', () {
    final out = groupBySessionId([
      {'session_id': 's1', 'task': 'a'},
      {'session_id': 's1', 'task': 'b'},
      {'session_id': 's2', 'task': 'c'},
    ]);
    expect(out.keys.toList()..sort(), ['s1', 's2']);
    expect(out['s1']!.length, 2);
    expect(out['s2']!.length, 1);
  });

  test('rows without session_id are silently skipped', () {
    // Defensive: a malformed row from the DB shouldn't poison the
    // whole export — just skip it.
    final out = groupBySessionId([
      {'session_id': 's1', 'task': 'a'},
      {'task': 'orphan'},
      {'session_id': 's2', 'task': 'b'},
    ]);
    expect(out['s1']!.length, 1);
    expect(out['s2']!.length, 1);
    expect(out.length, 2);
  });

  test('preserves row order within a session', () {
    // The export iterates sessions in started_at desc; rows within
    // a session should keep whatever order Supabase returned.
    final out = groupBySessionId([
      {'session_id': 's1', 'i': 1},
      {'session_id': 's1', 'i': 2},
      {'session_id': 's1', 'i': 3},
    ]);
    expect(
      out['s1']!.map((r) => r['i']).toList(),
      [1, 2, 3],
    );
  });

  test('large batch groups correctly', () {
    final rows = <Map<String, dynamic>>[];
    for (var i = 0; i < 100; i++) {
      rows.add({
        'session_id': i % 5 == 0 ? 's_other' : 's_main',
        'i': i,
      });
    }
    final out = groupBySessionId(rows);
    expect(out['s_main']!.length, 80);
    expect(out['s_other']!.length, 20);
  });
}