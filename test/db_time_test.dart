import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/models/homework_session.dart';
import 'package:donefirst/utils/db_time.dart';

/// Every timestamp column in this schema is `timestamptz` and
/// PostgREST reads an offset-less ISO string as UTC. Writing
/// `DateTime.now().toIso8601String()` therefore shifted every
/// client-written timestamp by the device's UTC offset.
///
/// It showed up as `ended_at` landing *before* `started_at`:
/// `endSession` wrote local time while `started_at` came from the
/// column's `DEFAULT now()`, so a session on a UTC-4 machine recorded
/// 14:32 → 12:32. Durations derived from the pair went negative, and
/// the same shift expired pairing codes and approved breaks hours
/// early.
void main() {
  test('dbNow is an absolute instant, not a local wall clock', () {
    final s = dbNow();
    expect(
      s.endsWith('Z'),
      isTrue,
      reason: 'without the offset Postgres reads this as UTC and shifts it',
    );
    // Parses back to within a second of the same instant.
    final parsed = DateTime.parse(s);
    expect(parsed.isUtc, isTrue);
    expect(
      DateTime.now().toUtc().difference(parsed).inSeconds.abs(),
      lessThan(2),
    );
  });

  test('dbTime preserves the instant across the local/UTC boundary', () {
    final local = DateTime(2026, 7, 28, 12, 32, 46);
    final round = DateTime.parse(dbTime(local));
    expect(round.isAtSameMomentAs(local), isTrue);
  });

  test('a session written now cannot end before it started', () {
    // The exact shape of the corrupt row found in production: the
    // server stamps started_at in UTC, the client stamps ended_at.
    // Off a UTC-4 machine the old code produced ended < started.
    final startedAt = DateTime.now().toUtc();
    final endedAt = DateTime.parse(dbNow());
    expect(endedAt.isBefore(startedAt), isFalse);
  });

  test('HomeworkSession.toMap serialises both ends in UTC', () {
    final session = HomeworkSession(
      id: 's1',
      childId: 'c1',
      parentId: 'p1',
      status: 'completed',
      startedAt: DateTime(2026, 7, 28, 10, 32),
      endedAt: DateTime(2026, 7, 28, 12, 32),
      minLockMinutes: 45,
    );
    final map = session.toMap();
    expect((map['started_at'] as String).endsWith('Z'), isTrue);
    expect((map['ended_at'] as String).endsWith('Z'), isTrue);
    // And the ordering survives the trip, which is the whole point.
    expect(
      DateTime.parse(map['ended_at'] as String).isAfter(
        DateTime.parse(map['started_at'] as String),
      ),
      isTrue,
    );
  });
}
